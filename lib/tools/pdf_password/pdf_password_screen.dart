import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../core/services/file_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/file_drop_zone.dart';
import '../../core/widgets/stamp_animation.dart';
import '../../core/widgets/task_progress_dialog.dart';
import 'pdf_password_controller.dart';
import 'pdf_password_state.dart';

class PdfPasswordScreen extends ConsumerStatefulWidget {
  const PdfPasswordScreen({super.key});

  @override
  ConsumerState<PdfPasswordScreen> createState() => _PdfPasswordScreenState();
}

class _PdfPasswordScreenState extends ConsumerState<PdfPasswordScreen> {
  final FileService _fileService = FileService();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _obscureRemovalPassword = true;

  Future<void> _handleSubmit() async {
    final controller = ref.read(pdfPasswordControllerProvider.notifier);
    final state = ref.read(pdfPasswordControllerProvider);
    final isAdd = state.mode == PdfPasswordMode.add;
    await showTaskProgressDialog<String>(
      context: context,
      title: isAdd ? 'Protecting PDF' : 'Removing Protection',
      defaultMessage: isAdd ? 'Encrypting file…' : 'Decrypting file…',
      getMessage: () => ref.read(pdfPasswordControllerProvider).progressMessage ?? (isAdd ? 'Encrypting file…' : 'Decrypting file…'),
      task: () => controller.submit(),
    );
  }

  Future<void> _pickFile() async {
    final files = await _fileService.pickPdfFiles(allowMultiple: false);
    if (files.isNotEmpty) {
      ref.read(pdfPasswordControllerProvider.notifier).loadDocument(files.first);
    }
  }

  Future<void> _handleSaveAs(String currentOutputPath) async {
    final savedPath = await _fileService.saveFile(
      defaultFileName: p.basename(currentOutputPath),
      bytes: [],
    );

    if (savedPath != null && mounted) {
      try {
        final src = File(currentOutputPath);
        if (src.existsSync()) {
          await src.copy(savedPath);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved to $savedPath'),
                backgroundColor: AppColors.anvilTeal,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not save file: $e'),
              backgroundColor: AppColors.rustRed,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final state = ref.watch(pdfPasswordControllerProvider);
    final controller = ref.read(pdfPasswordControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background(brightness),
      appBar: AppBar(
        title: Text(
          'Password Protect PDF',
          style: AppTypography.displayMedium(brightness),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (state.isLoaded)
            IconButton(
              tooltip: 'Reset',
              icon: const Icon(Icons.refresh),
              onPressed: controller.reset,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.errorMessage != null)
                _buildErrorBanner(context, state.errorMessage!, brightness, controller),
              Expanded(
                child: !state.isLoaded
                    ? _buildEmptyDropZone(brightness)
                    : state.outputPath != null
                        ? _buildSuccessView(context, state, brightness, controller)
                        : _buildPasswordForm(context, state, brightness, controller),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(
    BuildContext context,
    String message,
    Brightness brightness,
    PdfPasswordController controller,
  ) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.rustRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: AppColors.rustRed, width: 4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.rustRed),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium(brightness).copyWith(
                color: AppColors.text(brightness),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: controller.clearError,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDropZone(Brightness brightness) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 280),
        child: FileDropZone(
          onTap: _pickFile,
          label: 'Drop PDF file here or click to browse',
          sublabel: 'Select a PDF document to add or remove password protection',
          icon: Icons.lock_outline_rounded,
        ),
      ),
    );
  }

  Widget _buildPasswordForm(
    BuildContext context,
    PdfPasswordState state,
    Brightness brightness,
    PdfPasswordController controller,
  ) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // File Header Card
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground(brightness),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.pegGrey),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: state.isProtected
                              ? AppColors.sparkYellow.withValues(alpha: 0.15)
                              : AppColors.anvilTeal.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          state.isProtected ? Icons.lock_rounded : Icons.lock_open_rounded,
                          size: 28,
                          color: state.isProtected ? AppColors.sparkYellow : AppColors.anvilTeal,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.file?.name ?? 'Document.pdf',
                              style: AppTypography.bodyLarge(brightness).copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  state.formattedFileSize,
                                  style: AppTypography.mono(brightness).copyWith(
                                    fontSize: 12,
                                    color: AppColors.text(brightness).withValues(alpha: 0.7),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: state.isProtected
                                        ? AppColors.sparkYellow.withValues(alpha: 0.15)
                                        : AppColors.anvilTeal.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    state.isProtected ? 'Password Protected' : 'Unprotected',
                                    style: AppTypography.mono(brightness).copyWith(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: state.isProtected
                                          ? AppColors.sparkYellow
                                          : AppColors.anvilTeal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        label: const Text('Change'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Form Body based on Mode
                if (state.mode == PdfPasswordMode.add) ...[
                  Text(
                    'SET NEW PASSWORD',
                    style: AppTypography.labelSmall(brightness),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    obscureText: _obscurePassword,
                    onChanged: controller.setPassword,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      hintText: 'Enter at least 6 characters',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    obscureText: _obscureConfirmPassword,
                    onChanged: controller.setConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      hintText: 'Re-enter password',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Validation Message
                  if (state.password.isNotEmpty && state.isPasswordTooShort)
                    Text(
                      '• Password must be at least ${PdfPasswordState.minPasswordLength} characters.',
                      style: AppTypography.bodyMedium(brightness).copyWith(
                        fontSize: 12,
                        color: AppColors.rustRed,
                      ),
                    )
                  else if (state.confirmPassword.isNotEmpty && !state.passwordsMatch)
                    Text(
                      '• Passwords do not match.',
                      style: AppTypography.bodyMedium(brightness).copyWith(
                        fontSize: 12,
                        color: AppColors.rustRed,
                      ),
                    )
                  else
                    Text(
                      'Use at least 6 characters. Standard PDF viewers will prompt for this password when opened.',
                      style: AppTypography.bodyMedium(brightness).copyWith(
                        fontSize: 12,
                        color: AppColors.text(brightness).withValues(alpha: 0.6),
                      ),
                    ),

                  const SizedBox(height: 32),

                  AppButton(
                    label: 'Protect PDF',
                    icon: Icons.lock_rounded,
                    variant: AppButtonVariant.primary,
                    isLoading: state.isProcessing,
                    onPressed: state.canSubmitAdd ? _handleSubmit : null,
                  ),
                ] else ...[
                  Text(
                    'REMOVE PROTECTION',
                    style: AppTypography.labelSmall(brightness),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    obscureText: _obscureRemovalPassword,
                    onChanged: controller.setRemovalPassword,
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      hintText: 'Enter existing PDF password',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.key_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureRemovalPassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureRemovalPassword = !_obscureRemovalPassword;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the current password to decrypt and remove protection. Anvil will not bypass missing passwords.',
                    style: AppTypography.bodyMedium(brightness).copyWith(
                      fontSize: 12,
                      color: AppColors.text(brightness).withValues(alpha: 0.6),
                    ),
                  ),

                  const SizedBox(height: 32),

                  AppButton(
                    label: 'Remove Protection',
                    icon: Icons.lock_open_rounded,
                    variant: AppButtonVariant.primary,
                    isLoading: state.isProcessing,
                    onPressed: state.canSubmitRemove ? _handleSubmit : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessView(
    BuildContext context,
    PdfPasswordState state,
    Brightness brightness,
    PdfPasswordController controller,
  ) {
    final isAddedMode = state.mode == PdfPasswordMode.add;
    final stampLabel = isAddedMode ? 'PROTECTED' : 'UNPROTECTED';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StampAnimation(label: stampLabel),
            const SizedBox(height: 24),
            Text(
              isAddedMode ? 'Password Protection Added!' : 'Password Protection Removed!',
              style: AppTypography.displayMedium(brightness),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBackground(brightness),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.pegGrey),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.outputPath != null
                              ? p.basename(state.outputPath!)
                              : 'document.pdf',
                          style: AppTypography.bodyMedium(brightness).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isAddedMode
                              ? 'File is encrypted with your user password.'
                              : 'File can now be opened without a password.',
                          style: AppTypography.bodyMedium(brightness).copyWith(
                            fontSize: 13,
                            color: AppColors.text(brightness).withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (state.outputPath != null) ...[
              const SizedBox(height: 16),
              Text(
                'Saved to:',
                style: AppTypography.labelSmall(brightness),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxWidth: 520),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.pegGrey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(color: AppColors.pegGrey.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  state.outputPath!,
                  style: AppTypography.mono(brightness).copyWith(
                    fontSize: 12,
                    color: AppColors.text(brightness),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                AppButton(
                  label: 'Open Folder',
                  icon: Icons.folder_open_rounded,
                  variant: AppButtonVariant.primary,
                  onPressed: () {
                    if (state.outputPath != null) {
                      _fileService.openFolder(p.dirname(state.outputPath!));
                    }
                  },
                ),
                AppButton(
                  label: 'Save As…',
                  icon: Icons.save_alt_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    if (state.outputPath != null) {
                      _handleSaveAs(state.outputPath!);
                    }
                  },
                ),
                AppButton(
                  label: 'Share',
                  icon: Icons.share_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    if (state.outputPath != null) {
                      _fileService.shareFile(state.outputPath!);
                    }
                  },
                ),
                AppButton(
                  label: 'Process Another PDF',
                  icon: Icons.refresh,
                  variant: AppButtonVariant.secondary,
                  onPressed: controller.reset,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
