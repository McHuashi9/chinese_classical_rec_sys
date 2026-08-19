import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:chinese_classical_rec_sys/engine/feedback_mailto.dart';
import 'package:chinese_classical_rec_sys/engine/feedback_submit.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 打开反馈表单弹窗。
///
/// [diagnosticsLoader] 和 [mailtoLauncher] 可注入，便于测试。
Future<void> showFeedbackDialog(
  BuildContext context, {
  required String appVersion,
  required String platform,
  required String contentDataVersion,
  required String schemaVersions,
  Future<String> Function()? diagnosticsLoader,
  Future<String> Function()? logTailLoader,
  Future<bool> Function(Uri uri)? mailtoLauncher,
  Future<FeedbackSubmitResult> Function(FeedbackDraft draft)? submitFeedback,
}) {
  final loadLogTail = logTailLoader ?? readLogTail;
  return showDialog<void>(
    context: context,
    builder: (_) => FeedbackDialog(
      appVersion: appVersion,
      platformName: platform,
      contentDataVersion: contentDataVersion,
      schemaVersions: schemaVersions,
      diagnosticsLoader: diagnosticsLoader ??
          () async {
            final logTail = await loadLogTail();
            return buildDiagnosticText(
              appVersion: appVersion,
              platform: platform,
              contentDataVersion: contentDataVersion,
              schemaVersions: schemaVersions,
              logTail: logTail,
            );
          },
      logTailLoader: loadLogTail,
      mailtoLauncher: mailtoLauncher ?? _defaultMailtoLauncher,
      submitFeedback:
          submitFeedback ?? (draft) => submitFeedbackToWorker(draft: draft),
    ),
  );
}

Future<bool> _defaultMailtoLauncher(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// 反馈 Bug / 意见弹窗。
class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({
    super.key,
    required this.appVersion,
    required this.platformName,
    required this.contentDataVersion,
    required this.schemaVersions,
    required this.diagnosticsLoader,
    required this.logTailLoader,
    required this.mailtoLauncher,
    required this.submitFeedback,
  });

  final String appVersion;
  final String platformName;
  final String contentDataVersion;
  final String schemaVersions;
  final Future<String> Function() diagnosticsLoader;
  final Future<String> Function() logTailLoader;
  final Future<bool> Function(Uri uri) mailtoLauncher;
  final Future<FeedbackSubmitResult> Function(FeedbackDraft draft)
      submitFeedback;

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  late Future<String> _diagnosticsFuture;
  late Future<String> _logTailFuture;
  String _type = 'Bug';
  bool _diagnosticsExpanded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _diagnosticsFuture = widget.diagnosticsLoader();
    _logTailFuture = widget.logTailLoader();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool _validate() {
    final ok = _formKey.currentState?.validate() ?? false;
    if (ok) _formKey.currentState?.save();
    return ok;
  }

  Future<String> _diagnostics() => _diagnosticsFuture;

  Future<FeedbackDraft> _draft() async {
    final diagnostics = await _diagnostics();
    final logTail = await _logTailFuture;
    return FeedbackDraft(
      type: _type,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      diagnostics: diagnostics,
      appVersion: widget.appVersion,
      platform: widget.platformName,
      contentDataVersion: widget.contentDataVersion,
      schemaVersions: widget.schemaVersions,
      logTail: logTail,
    );
  }

  Future<void> _openMailClient() async {
    if (!_validate()) return;
    final draft = await _draft();
    final uri = Uri.parse(buildMailtoUri(
      recipient: kFeedbackRecipient,
      subject: draft.subject,
      body: draft.body,
    ));

    setState(() => _busy = true);
    final ok = await widget.mailtoLauncher(uri);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未找到可用的邮件客户端，请复制完整反馈内容后到任意邮箱发送'),
        ),
      );
    }
  }

  Future<void> _copyFullFeedback() async {
    if (!_validate()) return;
    final draft = await _draft();
    final text = buildFullFeedbackText(
      recipient: kFeedbackRecipient,
      draft: draft,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('完整反馈内容已复制')),
    );
  }

  Future<void> _copyDiagnostics() async {
    final diagnostics = await _diagnostics();
    await Clipboard.setData(ClipboardData(text: diagnostics));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('诊断信息已复制')),
    );
  }

  // ignore: unused_element
  Future<void> _submitOnline() async {
    if (!_validate()) return;
    setState(() => _busy = true);
    final draft = await _draft();
    final result = await widget.submitFeedback(draft);
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交，感谢反馈')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('提交失败：${result.error}，请使用复制/邮件方式'),
        ),
      );
    }
  }

  Future<void> _copyEmail() async {
    await Clipboard.setData(const ClipboardData(text: kFeedbackRecipient));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('邮箱已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryColor = context.appColors.inkSecondary;

    return AlertDialog(
      title: const Text('反馈 Bug / 意见'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _type,
                        decoration: const InputDecoration(labelText: '类型'),
                        items: const [
                          DropdownMenuItem(value: 'Bug', child: Text('Bug')),
                          DropdownMenuItem(value: '建议', child: Text('建议')),
                        ],
                        onChanged: (value) {
                          if (value != null) setState(() => _type = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(labelText: '标题 *'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? '请填写标题'
                                : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: '描述 *',
                          alignLabelWithHint: true,
                        ),
                        maxLines: 4,
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? '请填写描述'
                                : null,
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => setState(
                            () => _diagnosticsExpanded = !_diagnosticsExpanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                _diagnosticsExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                                color: context.accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '诊断信息预览',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: context.accent),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_diagnosticsExpanded)
                        FutureBuilder<String>(
                          future: _diagnosticsFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: LinearProgressIndicator(),
                              );
                            }
                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                snapshot.data ?? '（无法读取诊断信息）',
                                style: theme.textTheme.bodySmall,
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 8),
                      Text(
                        '默认邮件客户端不是你想用的？请点“复制完整反馈内容”，到任意网页邮箱粘贴发送。',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: secondaryColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  // TODO: R2 开通并部署后启用在线提交。
                  onPressed: null,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: const Text('在线提交到开发者（方便）'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openMailClient,
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: const Text('打开默认邮件客户端'),
                ),
                OutlinedButton.icon(
                  onPressed: _copyFullFeedback,
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('复制完整反馈内容'),
                ),
                OutlinedButton.icon(
                  onPressed: _copyDiagnostics,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('复制诊断信息'),
                ),
                TextButton.icon(
                  onPressed: _copyEmail,
                  icon: const Icon(Icons.email_outlined, size: 18),
                  label: const Text('复制邮箱地址'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
