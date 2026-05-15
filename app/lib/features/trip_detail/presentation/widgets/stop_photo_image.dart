import 'package:flutter/material.dart';
import 'package:trip_planner_app/features/trip_detail/data/stop_photo_service.dart';
import 'package:trip_planner_app/features/trips/data/models/trip_model.dart';

class StopPhotoImage extends StatefulWidget {
  const StopPhotoImage({
    super.key,
    required this.photo,
    required this.imageBuilder,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final StopPhoto photo;
  final Widget Function(BuildContext context, String imageUrl) imageBuilder;
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  State<StopPhotoImage> createState() => _StopPhotoImageState();
}

class _StopPhotoImageState extends State<StopPhotoImage> {
  final StopPhotoService _photoService = StopPhotoService.instance;
  late Future<StopPhoto> _resolvedPhotoFuture;

  @override
  void initState() {
    super.initState();
    _resolvedPhotoFuture = _resolvePhoto();
  }

  @override
  void didUpdateWidget(covariant StopPhotoImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.storagePath != widget.photo.storagePath ||
        oldWidget.photo.url != widget.photo.url ||
        oldWidget.photo.signedUrlExpiresAt != widget.photo.signedUrlExpiresAt) {
      _resolvedPhotoFuture = _resolvePhoto();
    }
  }

  Future<StopPhoto> _resolvePhoto() {
    return _photoService.ensureActiveUrl(widget.photo);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StopPhoto>(
      future: _resolvedPhotoFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return widget.imageBuilder(context, snapshot.data!.url);
        }

        if (widget.photo.hasDisplayUrl) {
          return widget.imageBuilder(context, widget.photo.url);
        }

        if (snapshot.hasError) {
          return widget.errorBuilder?.call(context, snapshot.error!) ??
              const SizedBox.shrink();
        }

        return widget.loadingBuilder?.call(context) ?? const SizedBox.shrink();
      },
    );
  }
}
