// lib/src/screens/settings/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:auralens/src/screens/camera/camera_view_model.dart'; // CameraViewModel에 접근
import 'package:auralens/src/models/camera_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('설정', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white), // 뒤로가기 버튼 색상
      ),
      backgroundColor: Colors.black, // 배경색 통일
      body: Consumer<CameraViewModel>(
        builder: (context, viewModel, child) {
          return ListView(
            children: [
              _buildSectionTitle(context, '구도 가이드'),
              SwitchListTile(
                title: const Text('그리드 표시', style: TextStyle(color: Colors.white)),
                value: viewModel.isGridEnabled,
                onChanged: (value) {
                  viewModel.toggleGrid(value); // ViewModel에 값 전달
                },
                activeThumbColor: Theme.of(context).colorScheme.primary, // 활성화 색상
              ),
              SwitchListTile(
                title: const Text('AI 어시스턴트 사용', style: TextStyle(color: Colors.white)),
                value: viewModel.isAiAssistEnabled,
                onChanged: (value) {
                  viewModel.toggleAiAssist(value); // ViewModel에 값 전달
                },
                activeThumbColor: Theme.of(context).colorScheme.primary,
              ),
              // TODO: AI 구도 가이드 모드 선택 (RadioListTile 등으로 구현)
              // 현재는 3x3 그리드와 AI 어시스트의 단순 토글만 있지만,
              // '삼각형 구도', '황금 분할' 등을 선택하는 RadioListTile을 여기에 추가할 수 있습니다.
              // 예를 들어, viewModel.compositionMode = CompositionMode.triangular;

              _buildSectionTitle(context, '카메라 설정'),
              ListTile(
                title: const Text('사진 해상도', style: TextStyle(color: Colors.white)),
                subtitle: Text(viewModel.cameraResolution.name, style: TextStyle(color: Colors.grey)), // 현재 해상도 표시
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                onTap: () {
                  // TODO: 해상도 선택 다이얼로그 띄우기
                  _showResolutionSelectionDialog(context, viewModel);
                },
              ),

              _buildSectionTitle(context, '정보'),
              ListTile(
                title: const Text('앱 버전', style: TextStyle(color: Colors.white)),
                subtitle: const Text('1.0.0 (Beta)', style: TextStyle(color: Colors.grey)),
              ),
              ListTile(
                title: const Text('개발자 정보', style: TextStyle(color: Colors.white)),
                onTap: () {
                  // TODO: 개발자 정보 페이지 또는 다이얼로그
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 24.0, bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showResolutionSelectionDialog(BuildContext context, CameraViewModel viewModel) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[850], // 다이얼로그 배경색
          title: const Text('사진 해상도 선택', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: CameraResolution.values.map((resolution) {
              return RadioListTile<CameraResolution>(
                title: Text(resolution.name, style: const TextStyle(color: Colors.white)),
                value: resolution,
                groupValue: viewModel.cameraResolution,
                onChanged: (CameraResolution? newResolution) {
                  if (newResolution != null) {
                    viewModel.setCameraResolution(newResolution);
                    Navigator.of(dialogContext).pop(); // 다이얼로그 닫기
                  }
                },
                activeColor: Theme.of(context).colorScheme.primary,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
