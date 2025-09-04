// lib/widgets/loading_indicator.dart

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class LoadingIndicator extends StatelessWidget {
  final double size;

  const LoadingIndicator({super.key, this.size = 150.0});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Lottie.asset(
        'assets/splash/booka_equalizer_loader.json',
        width: size,
        height: size,
      ),
    );
  }
}