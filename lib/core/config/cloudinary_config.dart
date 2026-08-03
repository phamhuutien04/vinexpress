class CloudinaryConfig {
  CloudinaryConfig._();

  static const cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'dzjm9ea2',
  );

  static const uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'vinexpress_evidence',
  );

  static Uri get imageUploadUri =>
      Uri.https('api.cloudinary.com', '/v1_1/$cloudName/image/upload');
}
