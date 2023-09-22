#include <ArduinoJson.h>

extern "C" int fuzz_main(uint32_t size, const uint8_t *data) {
  DynamicJsonDocument doc(4096);
  DeserializationError error = deserializeJson(doc, data, size);
  //if (!error) {
  //  std::string json;
  //  serializeJson(doc, json);
  //}
  return !error;
}
