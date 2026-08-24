#include <jni.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <dlfcn.h>
#include <mutex>
#include <string>
#include <vector>

namespace {

struct SherpaOnnxOnlineRecognizer;
struct SherpaOnnxOnlineStream;

struct FeatureConfig {
  int32_t sample_rate;
  int32_t feature_dim;
};

struct OnlineTransducerModelConfig {
  const char* encoder;
  const char* decoder;
  const char* joiner;
};

struct OnlineParaformerModelConfig {
  const char* encoder;
  const char* decoder;
};

struct OnlineZipformer2CtcModelConfig {
  const char* model;
};

struct OnlineNemoCtcModelConfig {
  const char* model;
};

struct OnlineToneCtcModelConfig {
  const char* model;
};

struct OnlineModelConfig {
  OnlineTransducerModelConfig transducer;
  OnlineParaformerModelConfig paraformer;
  OnlineZipformer2CtcModelConfig zipformer2_ctc;
  const char* tokens;
  int32_t num_threads;
  const char* provider;
  int32_t debug;
  const char* model_type;
  const char* modeling_unit;
  const char* bpe_vocab;
  const char* tokens_buf;
  int32_t tokens_buf_size;
  OnlineNemoCtcModelConfig nemo_ctc;
  OnlineToneCtcModelConfig tone_ctc;
};

struct OnlineCtcFstDecoderConfig {
  const char* graph;
  int32_t max_active;
};

struct HomophoneReplacerConfig {
  const char* dict_dir;
  const char* lexicon;
  const char* rule_fsts;
};

struct OnlineRecognizerConfig {
  FeatureConfig feat;
  OnlineModelConfig model;
  const char* decoding_method;
  int32_t max_active_paths;
  int32_t enable_endpoint;
  float rule1_min_trailing_silence;
  float rule2_min_trailing_silence;
  float rule3_min_utterance_length;
  const char* hotwords_file;
  float hotwords_score;
  OnlineCtcFstDecoderConfig ctc_fst_decoder_config;
  const char* rule_fsts;
  const char* rule_fars;
  float blank_penalty;
  const char* hotwords_buf;
  int32_t hotwords_buf_size;
  HomophoneReplacerConfig hr;
};

using CreateOnlineRecognizer = SherpaOnnxOnlineRecognizer* (*)(
    const OnlineRecognizerConfig*);
using DestroyOnlineRecognizer = void (*)(SherpaOnnxOnlineRecognizer*);
using CreateOnlineStream = SherpaOnnxOnlineStream* (*)(
    SherpaOnnxOnlineRecognizer*);
using DestroyOnlineStream = void (*)(SherpaOnnxOnlineStream*);
using OnlineStreamAcceptWaveform = void (*)(SherpaOnnxOnlineStream*, int32_t,
                                             const float*, int32_t);
using OnlineStreamInputFinished = void (*)(SherpaOnnxOnlineStream*);
using IsOnlineStreamReady = int32_t (*)(SherpaOnnxOnlineRecognizer*,
                                         SherpaOnnxOnlineStream*);
using DecodeOnlineStream = void (*)(SherpaOnnxOnlineRecognizer*,
                                    SherpaOnnxOnlineStream*);
using GetOnlineStreamResultAsJson = const char* (*)(
    SherpaOnnxOnlineRecognizer*, SherpaOnnxOnlineStream*);
using DestroyOnlineStreamResultJson = void (*)(const char*);
using ResetOnlineStream = void (*)(SherpaOnnxOnlineRecognizer*,
                                   SherpaOnnxOnlineStream*);
using IsEndpoint = int32_t (*)(SherpaOnnxOnlineRecognizer*,
                               SherpaOnnxOnlineStream*);

struct SherpaApi {
  void* c_api = nullptr;
  void* cxx_api = nullptr;
  CreateOnlineRecognizer create_online_recognizer = nullptr;
  DestroyOnlineRecognizer destroy_online_recognizer = nullptr;
  CreateOnlineStream create_online_stream = nullptr;
  DestroyOnlineStream destroy_online_stream = nullptr;
  OnlineStreamAcceptWaveform online_stream_accept_waveform = nullptr;
  OnlineStreamInputFinished online_stream_input_finished = nullptr;
  IsOnlineStreamReady is_online_stream_ready = nullptr;
  DecodeOnlineStream decode_online_stream = nullptr;
  GetOnlineStreamResultAsJson get_online_stream_result_as_json = nullptr;
  DestroyOnlineStreamResultJson destroy_online_stream_result_json = nullptr;
  ResetOnlineStream reset_online_stream = nullptr;
  IsEndpoint is_endpoint = nullptr;
};

template <typename T>
T loadSymbol(void* library, const char* name) {
  return reinterpret_cast<T>(dlsym(library, name));
}

bool loadApi(SherpaApi* api) {
  static std::once_flag once;
  static SherpaApi shared;
  static bool loaded = false;
  std::call_once(once, [&]() {
    // The C API shared object has a dependency on the C++ API object. Loading
    // both explicitly keeps Android's linker namespace deterministic across
    // the Flutter plugin's ABI-specific JNI libraries.
    shared.cxx_api = dlopen("libsherpa-onnx-cxx-api.so", RTLD_NOW | RTLD_LOCAL);
    shared.c_api = dlopen("libsherpa-onnx-c-api.so", RTLD_NOW | RTLD_LOCAL);
    if (shared.c_api == nullptr) return;

    shared.create_online_recognizer = loadSymbol<CreateOnlineRecognizer>(
        shared.c_api, "SherpaOnnxCreateOnlineRecognizer");
    shared.destroy_online_recognizer = loadSymbol<DestroyOnlineRecognizer>(
        shared.c_api, "SherpaOnnxDestroyOnlineRecognizer");
    shared.create_online_stream =
        loadSymbol<CreateOnlineStream>(shared.c_api, "SherpaOnnxCreateOnlineStream");
    shared.destroy_online_stream =
        loadSymbol<DestroyOnlineStream>(shared.c_api, "SherpaOnnxDestroyOnlineStream");
    shared.online_stream_accept_waveform =
        loadSymbol<OnlineStreamAcceptWaveform>(
            shared.c_api, "SherpaOnnxOnlineStreamAcceptWaveform");
    shared.online_stream_input_finished =
        loadSymbol<OnlineStreamInputFinished>(
            shared.c_api, "SherpaOnnxOnlineStreamInputFinished");
    shared.is_online_stream_ready = loadSymbol<IsOnlineStreamReady>(
        shared.c_api, "SherpaOnnxIsOnlineStreamReady");
    shared.decode_online_stream =
        loadSymbol<DecodeOnlineStream>(shared.c_api, "SherpaOnnxDecodeOnlineStream");
    shared.get_online_stream_result_as_json =
        loadSymbol<GetOnlineStreamResultAsJson>(
            shared.c_api, "SherpaOnnxGetOnlineStreamResultAsJson");
    shared.destroy_online_stream_result_json =
        loadSymbol<DestroyOnlineStreamResultJson>(
            shared.c_api, "SherpaOnnxDestroyOnlineStreamResultJson");
    shared.reset_online_stream = loadSymbol<ResetOnlineStream>(
        shared.c_api, "SherpaOnnxOnlineStreamReset");
    shared.is_endpoint =
        loadSymbol<IsEndpoint>(shared.c_api, "SherpaOnnxOnlineStreamIsEndpoint");

    loaded = shared.create_online_recognizer != nullptr &&
             shared.destroy_online_recognizer != nullptr &&
             shared.create_online_stream != nullptr &&
             shared.destroy_online_stream != nullptr &&
             shared.online_stream_accept_waveform != nullptr &&
             shared.online_stream_input_finished != nullptr &&
             shared.is_online_stream_ready != nullptr &&
             shared.decode_online_stream != nullptr &&
             shared.get_online_stream_result_as_json != nullptr &&
             shared.destroy_online_stream_result_json != nullptr &&
             shared.reset_online_stream != nullptr && shared.is_endpoint != nullptr;
  });
  if (!loaded) return false;
  *api = shared;
  return true;
}

std::string joinPath(const std::string& directory, const char* file) {
  if (directory.empty()) return file;
  if (directory.back() == '/') return directory + file;
  return directory + "/" + file;
}

void appendUtf8(std::string* output, uint32_t codePoint) {
  if (codePoint <= 0x7f) {
    output->push_back(static_cast<char>(codePoint));
  } else if (codePoint <= 0x7ff) {
    output->push_back(static_cast<char>(0xc0 | (codePoint >> 6)));
    output->push_back(static_cast<char>(0x80 | (codePoint & 0x3f)));
  } else if (codePoint <= 0xffff) {
    output->push_back(static_cast<char>(0xe0 | (codePoint >> 12)));
    output->push_back(static_cast<char>(0x80 | ((codePoint >> 6) & 0x3f)));
    output->push_back(static_cast<char>(0x80 | (codePoint & 0x3f)));
  } else {
    output->push_back(static_cast<char>(0xf0 | (codePoint >> 18)));
    output->push_back(static_cast<char>(0x80 | ((codePoint >> 12) & 0x3f)));
    output->push_back(static_cast<char>(0x80 | ((codePoint >> 6) & 0x3f)));
    output->push_back(static_cast<char>(0x80 | (codePoint & 0x3f)));
  }
}

int hexValue(char value) {
  if (value >= '0' && value <= '9') return value - '0';
  if (value >= 'a' && value <= 'f') return value - 'a' + 10;
  if (value >= 'A' && value <= 'F') return value - 'A' + 10;
  return -1;
}

std::string extractText(const char* json) {
  if (json == nullptr) return {};
  const char* key = std::strstr(json, "\"text\"");
  if (key == nullptr) return {};
  const char* cursor = std::strchr(key + 6, ':');
  if (cursor == nullptr) return {};
  cursor++;
  while (*cursor == ' ' || *cursor == '\t' || *cursor == '\r' ||
         *cursor == '\n') {
    cursor++;
  }
  if (*cursor != '"') return {};
  cursor++;

  std::string output;
  while (*cursor != '\0') {
    if (*cursor == '"') return output;
    if (*cursor != '\\') {
      output.push_back(*cursor++);
      continue;
    }
    cursor++;
    switch (*cursor) {
      case '"':
        output.push_back('"');
        cursor++;
        break;
      case '\\':
        output.push_back('\\');
        cursor++;
        break;
      case '/':
        output.push_back('/');
        cursor++;
        break;
      case 'b':
        output.push_back('\b');
        cursor++;
        break;
      case 'f':
        output.push_back('\f');
        cursor++;
        break;
      case 'n':
        output.push_back('\n');
        cursor++;
        break;
      case 'r':
        output.push_back('\r');
        cursor++;
        break;
      case 't':
        output.push_back('\t');
        cursor++;
        break;
      case 'u': {
        uint32_t codePoint = 0;
        for (int i = 0; i < 4; i++) {
          const int value = hexValue(cursor[1 + i]);
          if (value < 0) return {};
          codePoint = (codePoint << 4) | static_cast<uint32_t>(value);
        }
        appendUtf8(&output, codePoint);
        cursor += 5;
        break;
      }
      default:
        return {};
    }
  }
  return {};
}

class NativeRecognizer {
 public:
  NativeRecognizer(SherpaApi api, SherpaOnnxOnlineRecognizer* recognizer,
                   SherpaOnnxOnlineStream* stream)
      : api_(api), recognizer_(recognizer), stream_(stream) {}

  ~NativeRecognizer() {
    if (stream_ != nullptr) api_.destroy_online_stream(stream_);
    if (recognizer_ != nullptr) api_.destroy_online_recognizer(recognizer_);
  }

  std::string acceptPcm16(const int8_t* bytes, int32_t length) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stream_ == nullptr || length < 2) return {};
    const int32_t sampleCount = length / 2;
    samples_.resize(static_cast<size_t>(sampleCount));
    for (int32_t index = 0; index < sampleCount; index++) {
      const uint16_t low = static_cast<uint8_t>(bytes[index * 2]);
      const uint16_t high = static_cast<uint8_t>(bytes[index * 2 + 1]);
      const int16_t sample = static_cast<int16_t>(low | (high << 8));
      samples_[static_cast<size_t>(index)] =
          static_cast<float>(sample) / 32768.0f;
    }
    api_.online_stream_accept_waveform(stream_, 16000, samples_.data(),
                                       sampleCount);
    decodeReadyLocked();
    const std::string text = resultTextLocked();
    if (text == last_emitted_text_) return {};
    last_emitted_text_ = text;
    return text;
  }

  bool isEndpoint() {
    std::lock_guard<std::mutex> lock(mutex_);
    return stream_ != nullptr && api_.is_endpoint(recognizer_, stream_) != 0;
  }

  std::string currentText() {
    std::lock_guard<std::mutex> lock(mutex_);
    return resultTextLocked();
  }

  std::string finish() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stream_ == nullptr) return {};
    api_.online_stream_input_finished(stream_);
    decodeReadyLocked();
    return resultTextLocked();
  }

  void reset() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stream_ == nullptr) return;
    api_.reset_online_stream(recognizer_, stream_);
    last_emitted_text_.clear();
  }

 private:
  void decodeReadyLocked() {
    while (api_.is_online_stream_ready(recognizer_, stream_) != 0) {
      api_.decode_online_stream(recognizer_, stream_);
    }
  }

  std::string resultTextLocked() {
    const char* json =
        api_.get_online_stream_result_as_json(recognizer_, stream_);
    if (json == nullptr) return {};
    const std::string text = extractText(json);
    api_.destroy_online_stream_result_json(json);
    return text;
  }

  SherpaApi api_;
  SherpaOnnxOnlineRecognizer* recognizer_;
  SherpaOnnxOnlineStream* stream_;
  std::vector<float> samples_;
  std::string last_emitted_text_;
  std::mutex mutex_;
};

void throwIllegalState(JNIEnv* env, const char* message) {
  jclass exception = env->FindClass("java/lang/IllegalStateException");
  if (exception != nullptr) env->ThrowNew(exception, message);
}

NativeRecognizer* fromHandle(jlong handle) {
  return reinterpret_cast<NativeRecognizer*>(handle);
}

}  // namespace

extern "C" JNIEXPORT jlong JNICALL
Java_com_naviwealth_naviwealth_NativeSherpaStreamingRecognizer_nativeCreate(
    JNIEnv* env, jobject /* object */, jstring model_directory) {
  if (model_directory == nullptr) {
    throwIllegalState(env, "Zipformer model directory is missing");
    return 0;
  }

  SherpaApi api;
  if (!loadApi(&api)) {
    throwIllegalState(env, "sherpa-onnx Android native library is unavailable");
    return 0;
  }

  const char* directory_chars = env->GetStringUTFChars(model_directory, nullptr);
  if (directory_chars == nullptr) return 0;
  const std::string directory(directory_chars);
  env->ReleaseStringUTFChars(model_directory, directory_chars);

  const std::string model_path = joinPath(directory, "model.int8.onnx");
  const std::string tokens_path = joinPath(directory, "tokens.txt");

  OnlineRecognizerConfig config{};
  config.feat.sample_rate = 16000;
  config.feat.feature_dim = 80;
  config.model.zipformer2_ctc.model = model_path.c_str();
  config.model.tokens = tokens_path.c_str();
  config.model.num_threads = 1;
  config.model.provider = "cpu";
  config.model.debug = 0;
  config.decoding_method = "greedy_search";
  config.max_active_paths = 4;
  config.enable_endpoint = 1;
  config.rule1_min_trailing_silence = 2.0f;
  config.rule2_min_trailing_silence = 0.8f;
  config.rule3_min_utterance_length = 20.0f;
  config.hotwords_score = 1.5f;
  config.ctc_fst_decoder_config.max_active = 3000;

  SherpaOnnxOnlineRecognizer* recognizer =
      api.create_online_recognizer(&config);
  if (recognizer == nullptr) {
    throwIllegalState(env, "sherpa-onnx could not load the Zipformer model");
    return 0;
  }
  SherpaOnnxOnlineStream* stream = api.create_online_stream(recognizer);
  if (stream == nullptr) {
    api.destroy_online_recognizer(recognizer);
    throwIllegalState(env, "sherpa-onnx could not create a recognition stream");
    return 0;
  }
  return reinterpret_cast<jlong>(new NativeRecognizer(api, recognizer, stream));
}

extern "C" JNIEXPORT void JNICALL
Java_com_naviwealth_naviwealth_NativeSherpaStreamingRecognizer_nativeDestroy(
    JNIEnv* /* env */, jobject /* object */, jlong handle) {
  delete fromHandle(handle);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_naviwealth_naviwealth_NativeSherpaStreamingRecognizer_nativeAcceptPcm16(
    JNIEnv* env, jobject /* object */, jlong handle, jbyteArray pcm16,
    jint length) {
  NativeRecognizer* recognizer = fromHandle(handle);
  if (recognizer == nullptr || pcm16 == nullptr || length <= 0) return nullptr;
  const jsize available = env->GetArrayLength(pcm16);
  const jint safe_length = std::min<jint>(length, available);
  // ASR decoding may run ONNX inference and block for longer than a JNI
  // critical-array section should remain pinned. A regular JNI array view is
  // allowed to copy or pin as appropriate for the VM without imposing the
  // critical-region restrictions on the inference call below.
  jbyte* bytes = env->GetByteArrayElements(pcm16, nullptr);
  if (bytes == nullptr) return nullptr;
  const std::string text = recognizer->acceptPcm16(
      reinterpret_cast<const int8_t*>(bytes), safe_length);
  env->ReleaseByteArrayElements(pcm16, bytes, JNI_ABORT);
  if (text.empty()) return nullptr;
  return env->NewStringUTF(text.c_str());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_naviwealth_naviwealth_NativeSherpaStreamingRecognizer_nativeIsEndpoint(
    JNIEnv* /* env */, jobject /* object */, jlong handle) {
  NativeRecognizer* recognizer = fromHandle(handle);
  return recognizer != nullptr && recognizer->isEndpoint() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_naviwealth_naviwealth_NativeSherpaStreamingRecognizer_nativeCurrentText(
    JNIEnv* env, jobject /* object */, jlong handle) {
  NativeRecognizer* recognizer = fromHandle(handle);
  if (recognizer == nullptr) return nullptr;
  const std::string text = recognizer->currentText();
  if (text.empty()) return nullptr;
  return env->NewStringUTF(text.c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_naviwealth_naviwealth_NativeSherpaStreamingRecognizer_nativeFinish(
    JNIEnv* env, jobject /* object */, jlong handle) {
  NativeRecognizer* recognizer = fromHandle(handle);
  if (recognizer == nullptr) return nullptr;
  const std::string text = recognizer->finish();
  if (text.empty()) return nullptr;
  return env->NewStringUTF(text.c_str());
}

extern "C" JNIEXPORT void JNICALL
Java_com_naviwealth_naviwealth_NativeSherpaStreamingRecognizer_nativeReset(
    JNIEnv* /* env */, jobject /* object */, jlong handle) {
  NativeRecognizer* recognizer = fromHandle(handle);
  if (recognizer != nullptr) recognizer->reset();
}
