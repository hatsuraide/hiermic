class Constants {
  static const String appVersion = '1.0.0';

  static const int controlPort = 7878;
  static const int audioPort   = 7879;

  static const int sampleRate = 48000;
  static const int channels   = 1;

  static const String mdnsServiceType = '_hiermic._tcp';

  // Audio packet header: seq(4) + ts(4) + channels(1) + sampleCount(2) = 11 bytes
  static const int packetHeaderSize = 11;

  // ~20ms of audio per UDP packet (960 samples @ 48kHz)
  static const int samplesPerPacket = 960;
  static const int bytesPerPacket   = samplesPerPacket * channels * 2; // PCM16LE
}
