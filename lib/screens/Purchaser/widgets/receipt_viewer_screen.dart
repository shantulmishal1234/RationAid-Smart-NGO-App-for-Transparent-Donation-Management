import 'package:flutter/material.dart';
import 'dart:io';

/// Full-screen receipt viewer for both local files and network images
class ReceiptViewerScreen extends StatelessWidget {
  final File? localImage;
  final String? networkUrl;
  final String title;

  const ReceiptViewerScreen({
    super.key,
    this.localImage,
    this.networkUrl,
    this.title = 'Receipt',
  }) : assert(
         localImage != null || networkUrl != null,
         'Either localImage or networkUrl must be provided',
       );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.8),
        elevation: 0,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: localImage != null
              ? Image.file(localImage!, fit: BoxFit.contain)
              : Image.network(
                  networkUrl!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Loading receipt...',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: Colors.red[300],
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Failed to load receipt',
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Go Back'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
