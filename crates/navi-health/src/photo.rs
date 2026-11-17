//! Decode untrusted picks once, correct EXIF orientation, bound decoded memory,
//! resize, and encode clean images without source metadata.

use std::io::Cursor;

use image::{
    DynamicImage, ImageDecoder, ImageReader, Limits, codecs::jpeg::JpegEncoder,
    imageops::FilterType, metadata::Orientation,
};
use serde::{Deserialize, Serialize};
use thiserror::Error;

pub const UPLOAD_EDGE: u32 = 1280;
pub const KEEP_EDGE: u32 = 960;
/// Capture also reads labels and screenshots, whose small text needs more pixels.
pub const CAPTURE_EDGE: u32 = 4096;
pub const CAPTURE_PIXELS: u32 = 4 * 1024 * 1024;
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
    let image = decode(bytes)?;
    let upload = encode(&fit(&image, UPLOAD_EDGE), 82)?;
    let keep = encode(&fit(&image, KEEP_EDGE), 80)?;
    if upload.len() > MAX_PHOTO_BYTES || keep.len() > MAX_PHOTO_BYTES {
        return Err(PhotoError::Size);
    }
    Ok((upload, keep))
}

/// Preserves legible text for capture and retry, without copying source metadata.
/// Prefer lossless PNG; photographic noise may require high-quality JPEG instead.
/// The stored copy matches the upload so a retry never adds another compression pass.
pub fn prepare_capture(bytes: &[u8]) -> Result<(Vec<u8>, Vec<u8>), PhotoError> {
    let image = decode(bytes)?;
    let scale = (CAPTURE_EDGE as f64 / image.width().max(image.height()) as f64)
        .min((CAPTURE_PIXELS as f64 / (image.width() as f64 * image.height() as f64)).sqrt())
        .min(1.0);
    let mut image = if scale < 1.0 {
        image.resize(
            ((image.width() as f64 * scale).floor() as u32).max(1),
            ((image.height() as f64 * scale).floor() as u32).max(1),
            FilterType::Lanczos3,
        )
    } else {
        image
    };
    loop {
        let mut png = Cursor::new(Vec::new());
        DynamicImage::ImageRgb8(image.to_rgb8())
            .write_to(&mut png, image::ImageFormat::Png)
            .map_err(|_| PhotoError::Encode)?;
        let png = png.into_inner();
        if png.len() <= MAX_PHOTO_BYTES {
            return Ok((png.clone(), png));
        }
        let jpeg = encode(&image, 95)?;
        if jpeg.len() <= MAX_PHOTO_BYTES {
            return Ok((jpeg.clone(), jpeg));
        }
        if image.width().max(image.height()) <= 960 {
            return Err(PhotoError::Size);
        }
        image = image.resize(
            (image.width() * 4 / 5).max(1),
            (image.height() * 4 / 5).max(1),
            FilterType::Lanczos3,
        );
    }
}

fn decode(bytes: &[u8]) -> Result<DynamicImage, PhotoError> {
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
    Ok(image)
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
    fn capture_preserves_long_screenshot_pixels_and_small_text_strokes() {
        let screenshot = image::RgbImage::from_fn(1080, 3200, |x, y| {
            // One-pixel strokes representing fine text survive lossless encoding.
            if (x % 11 == 0 || y % 17 == 0) && y % 40 < 15 {
                image::Rgb([0, 0, 0])
            } else {
                image::Rgb([255, 255, 255])
            }
        });
        let mut input = Cursor::new(Vec::new());
        DynamicImage::ImageRgb8(screenshot.clone())
            .write_to(&mut input, image::ImageFormat::Png)
            .unwrap();
        let (upload, keep) = prepare_capture(input.get_ref()).unwrap();
        assert!(upload.starts_with(b"\x89PNG\r\n\x1a\n"));
        assert_eq!(upload, keep, "retry uses the exact prepared image");
        assert_eq!(
            image::load_from_memory(&upload).unwrap().to_rgb8(),
            screenshot
        );
        assert!(upload.len() <= MAX_PHOTO_BYTES);
    }

    #[test]
    fn capture_noise_falls_back_to_jpeg_within_the_byte_budget() {
        let mut seed = 7_u32;
        let noisy = image::RgbImage::from_fn(1000, 750, |_, _| {
            let mut rgb = [0; 3];
            for channel in &mut rgb {
                seed ^= seed << 13;
                seed ^= seed >> 17;
                seed ^= seed << 5;
                *channel = seed as u8;
            }
            image::Rgb(rgb)
        });
        let mut input = Cursor::new(Vec::new());
        DynamicImage::ImageRgb8(noisy)
            .write_to(&mut input, image::ImageFormat::Png)
            .unwrap();
        assert!(input.get_ref().len() > MAX_PHOTO_BYTES);
        let (upload, keep) = prepare_capture(input.get_ref()).unwrap();
        assert!(
            upload.starts_with(&[0xff, 0xd8]),
            "input {} output {} prefix {:?}",
            input.get_ref().len(),
            upload.len(),
            &upload[..8]
        );
        assert_eq!(upload, keep);
        assert!(upload.len() <= MAX_PHOTO_BYTES);
        let output = image::load_from_memory(&upload).unwrap();
        assert_eq!((output.width(), output.height()), (1000, 750));
    }

    #[test]
    fn capture_bounds_dimensions_pixels_and_rejects_bad_input() {
        let (upload, _) = prepare_capture(&png(1600, 6000)).unwrap();
        let output = image::load_from_memory(&upload).unwrap();
        assert!(output.width().max(output.height()) <= CAPTURE_EDGE);
        assert!(
            u64::from(output.width()) * u64::from(output.height()) <= u64::from(CAPTURE_PIXELS)
        );
        assert!(upload.len() <= MAX_PHOTO_BYTES);
        assert_eq!(prepare_capture(b"not an image"), Err(PhotoError::Decode));
        assert_eq!(prepare_capture(&[]), Err(PhotoError::Size));
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
        let (capture, _) = prepare_capture(&tagged).unwrap();
        let upright = image::load_from_memory(&capture).unwrap();
        assert_eq!((upright.width(), upright.height()), (4, 8));
        assert!(!capture.windows(6).any(|part| part == b"Exif\0\0"));
    }
}
