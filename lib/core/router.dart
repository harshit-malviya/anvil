import 'package:go_router/go_router.dart';
import '../home/home_screen.dart';
import '../tools/pdf_merge/pdf_merge_screen.dart';
import '../tools/pdf_page_manager/pdf_page_manager_screen.dart';
import '../tools/pdf_split/pdf_split_screen.dart';
import '../tools/pdf_compress/pdf_compress_screen.dart';
import '../tools/pdf_to_image/pdf_to_image_screen.dart';
import '../tools/pdf_password/pdf_password_screen.dart';
import '../tools/pdf_insert_pages/pdf_insert_pages_screen.dart';
import '../tools/pdf_insert_image_as_page/pdf_insert_image_as_page_screen.dart';
import '../tools/images_to_pdf/images_to_pdf_screen.dart';
import '../tools/image_convert/image_convert_screen.dart';
import '../tools/image_resize/image_resize_screen.dart';
import '../tools/image_compress/image_compress_screen.dart';
import '../tools/image_blur/image_blur_screen.dart';
import '../tools/image_crop_rotate/image_crop_rotate_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/pdf-merge',
      builder: (context, state) => const PdfMergeScreen(),
    ),
    GoRoute(
      path: '/pdf-page-manager',
      builder: (context, state) => const PdfPageManagerScreen(),
    ),
    GoRoute(
      path: '/pdf-split',
      builder: (context, state) => const PdfSplitScreen(),
    ),
    GoRoute(
      path: '/pdf-compress',
      builder: (context, state) => const PdfCompressScreen(),
    ),
    GoRoute(
      path: '/pdf-to-image',
      builder: (context, state) => const PdfToImageScreen(),
    ),
    GoRoute(
      path: '/pdf-password',
      builder: (context, state) => const PdfPasswordScreen(),
    ),
    GoRoute(
      path: '/pdf-insert-pages',
      builder: (context, state) => const PdfInsertPagesScreen(),
    ),
    GoRoute(
      path: '/pdf-insert-image-as-page',
      builder: (context, state) => const PdfInsertImageAsPageScreen(),
    ),
    GoRoute(
      path: '/images-to-pdf',
      builder: (context, state) => const ImagesToPdfScreen(),
    ),
    GoRoute(
      path: '/image-convert',
      builder: (context, state) => const ImageConvertScreen(),
    ),
    GoRoute(
      path: '/image-resize',
      builder: (context, state) => const ImageResizeScreen(),
    ),
    GoRoute(
      path: '/image-compress',
      builder: (context, state) => const ImageCompressScreen(),
    ),
    GoRoute(
      path: '/image-blur',
      builder: (context, state) => const ImageBlurScreen(),
    ),
    GoRoute(
      path: '/image-crop-rotate',
      builder: (context, state) => const ImageCropRotateScreen(),
    ),
  ],
);


