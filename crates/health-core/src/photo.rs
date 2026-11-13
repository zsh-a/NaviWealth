//! Decode untrusted picks once, correct EXIF orientation, bound decoded memory,
//! resize, and encode clean JPEGs without source metadata.

use std::io::Cursor;

use image::{
    DynamicImage, ImageDecoder, ImageReader, Limits, codecs::jpeg::JpegEncoder,
    imageops::FilterType, metadata::Orientation,
};
use serde::{Deserialize, Serialize};
use thiserror::Error;

pub const UPLOAD_EDGE: u32 = 1280;
pub const KEEP_EDGE: u32 = 960;
pub const MAX_INPUT_BYTES: usize = 48 * 1024 * 1024;
pub const MAX_PHOTO_BYTES: usize = 2 * 1024 * 1024;
pub const MAX_PHOTOS: usize = 4;
pub const MAX_VIDEO_TIME_MS: u32 = 10_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum PhotoRole {
    #[default]
    Overview,
    Side,
    Detail,
    Label,
    AfterMeal,
}

impl PhotoRole {
    pub fn is_meal_view(self) -> bool {
        !matches!(self, Self::Label | Self::AfterMeal)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MealPhoto {
    pub bytes: Vec<u8>,
    #[serde(default)]
    pub role: PhotoRole,
    #[serde(default)]
    pub timestamp_ms: Option<u32>,
}

impl MealPhoto {
    pub fn new(bytes: Vec<u8>, role: PhotoRole, timestamp_ms: Option<u32>) -> Self {
        Self {
            bytes,
            role,
            timestamp_ms,
        }
    }

    pub fn validate(&self) -> Result<(), PhotoError> {
        if self.bytes.is_empty() || self.bytes.len() > MAX_PHOTO_BYTES {
            return Err(PhotoError::Size);
        }
        if self
            .timestamp_ms
            .is_some_and(|time| time > MAX_VIDEO_TIME_MS)
        {
            return Err(PhotoError::Timestamp);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Error)]
pub enum PhotoError {
    #[error("The photo size is outside the allowed range")]
    Size,
    #[error("The photo cannot be decoded safely")]
    Decode,
    #[error("The photo cannot be encoded")]
    Encode,
    #[error("The video frame timestamp is outside the clip")]
    Timestamp,
    #[error("Expected one to four views including a view of the meal")]
    Views,
}

pub fn validate_views(photos: &[MealPhoto]) -> Result<(), PhotoError> {
    if photos.is_empty()
        || photos.len() > MAX_PHOTOS
        || !photos.iter().any(|photo| photo.role.is_meal_view())
    {
        return Err(PhotoError::Views);
    }
    photos.iter().try_for_each(MealPhoto::validate)
}

/// Returns upload and local-storage JPEGs. The source metadata is never copied.
pub fn prepare(bytes: &[u8]) -> Result<(Vec<u8>, Vec<u8>), PhotoError> {
    if bytes.is_empty() || bytes.len() > MAX_INPUT_BYTES {
        return Err(PhotoError::Size);
    }
    let mut reader = ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| PhotoError::Decode)?;
    let mut limits = Limits::default();
    limits.max_image_width = Some(12_000);
    limits.max_image_height = Some(12_000);
    limits.max_alloc = Some(128 * 1024 * 1024);
    reader.limits(limits);
    let mut decoder = reader.into_decoder().map_err(|_| PhotoError::Decode)?;
    let orientation = decoder.orientation().unwrap_or(Orientation::NoTransforms);
    let mut image = DynamicImage::from_decoder(decoder).map_err(|_| PhotoError::Decode)?;
    image.apply_orientation(orientation);
    let upload = encode(&fit(&image, UPLOAD_EDGE), 82)?;
    let keep = encode(&fit(&image, KEEP_EDGE), 80)?;
    if upload.len() > MAX_PHOTO_BYTES || keep.len() > MAX_PHOTO_BYTES {
        return Err(PhotoError::Size);
    }
    Ok((upload, keep))
}

fn fit(image: &DynamicImage, edge: u32) -> DynamicImage {
    if image.width().max(image.height()) <= edge {
        image.clone()
    } else {
        image.resize(edge, edge, FilterType::Triangle)
    }
}

fn encode(image: &DynamicImage, quality: u8) -> Result<Vec<u8>, PhotoError> {
    let mut bytes = Vec::new();
    JpegEncoder::new_with_quality(&mut bytes, quality)
        .encode_image(&image.to_rgb8())
        .map_err(|_| PhotoError::Encode)?;
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png(width: u32, height: u32) -> Vec<u8> {
        let mut bytes = Cursor::new(Vec::new());
        DynamicImage::new_rgb8(width, height)
            .write_to(&mut bytes, image::ImageFormat::Png)
            .unwrap();
        bytes.into_inner()
    }

    #[test]
    fn preparation_resizes_and_strips_metadata() {
        let (upload, keep) = prepare(&png(2000, 1500)).unwrap();
        assert_eq!(&upload[..2], &[0xff, 0xd8]);
        let upload_image = image::load_from_memory(&upload).unwrap();
        let keep_image = image::load_from_memory(&keep).unwrap();
        assert_eq!((upload_image.width(), upload_image.height()), (1280, 960));
        assert_eq!((keep_image.width(), keep_image.height()), (960, 720));
        assert!(!upload.windows(6).any(|part| part == b"Exif\0\0"));
    }

    #[test]
    fn invalid_input_and_only_supporting_views_are_rejected() {
        assert_eq!(prepare(b"not an image"), Err(PhotoError::Decode));
        assert_eq!(prepare(&[]), Err(PhotoError::Size));
        let mut photo = MealPhoto::new(vec![1], PhotoRole::Label, None);
        assert_eq!(validate_views(&[photo.clone()]), Err(PhotoError::Views));
        photo.role = PhotoRole::Overview;
        photo.timestamp_ms = Some(10_001);
        assert_eq!(validate_views(&[photo]), Err(PhotoError::Timestamp));
    }

    #[test]
    fn orientation_is_applied_before_source_metadata_is_dropped() {
        let mut original = Vec::new();
        JpegEncoder::new(&mut original)
            .encode_image(&DynamicImage::new_rgb8(8, 4))
            .unwrap();
        // APP1 with a little-endian TIFF Orientation=6 (90 degrees clockwise).
        let exif: &[u8] =
            b"Exif\0\0II\x2a\0\x08\0\0\0\x01\0\x12\x01\x03\0\x01\0\0\0\x06\0\0\0\0\0\0\0";
        let mut tagged = vec![0xff, 0xd8, 0xff, 0xe1];
        tagged.extend_from_slice(&((exif.len() + 2) as u16).to_be_bytes());
        tagged.extend_from_slice(exif);
        tagged.extend_from_slice(&original[2..]);
        let (upload, _) = prepare(&tagged).unwrap();
        let upright = image::load_from_memory(&upload).unwrap();
        assert_eq!((upright.width(), upright.height()), (4, 8));
        assert!(!upload.windows(6).any(|part| part == b"Exif\0\0"));
    }
}
