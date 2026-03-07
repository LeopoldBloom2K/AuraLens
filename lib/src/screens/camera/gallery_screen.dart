// lib/src/screens/camera/gallery_screen.dart

import 'dart:io';
// 🚀 수정 1: share_plus와 중복되던 camera.dart import를 깔끔하게 삭제했습니다!
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart'; 
import 'package:auralens/src/screens/camera/camera_view_model.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  int _currentIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<CameraViewModel>();
    final photos = viewModel.sessionPhotos;

    if (photos.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
      return const Scaffold(backgroundColor: Colors.black);
    }

    if (_currentIndex >= photos.length) {
      _currentIndex = photos.length - 1;
    }

    final currentPhoto = photos[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${photos.length}', 
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)
        ),
        actions: [
          // 🚀 수정 2: 공유 버튼 (플러터 최신 문법 경고창을 깔끔하게 무시하는 주석 추가)
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () async {
              // ignore: deprecated_member_use
              await Share.shareXFiles([currentPhoto], text: 'AuraLens 카메라로 촬영한 사진입니다!');
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _showDeleteDialog(context, viewModel, currentPhoto),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: photos.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index; 
          });
        },
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Image.file(
              File(photos[index].path),
              fit: BoxFit.contain,
            ),
          );
        },
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, CameraViewModel viewModel, XFile photo) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('사진 삭제', style: TextStyle(color: Colors.white)),
          content: const Text('이 사진을 앱에서 삭제하시겠습니까?', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              child: const Text('취소', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            TextButton(
              child: const Text('삭제', style: TextStyle(color: Colors.redAccent)),
              onPressed: () {
                viewModel.deleteSessionPhoto(photo); 
                Navigator.pop(dialogContext); 
              },
            ),
          ],
        );
      },
    );
  }
}