import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';

class EmployeeRequestsContent extends StatefulWidget {
  final String employeeKey;
  final String employeeCode;
  final String employeeName;
  final String employeePhotoUrl;

  const EmployeeRequestsContent({
    super.key,
    required this.employeeKey,
    required this.employeeCode,
    required this.employeeName,
    this.employeePhotoUrl = '',
  });

  @override
  State<EmployeeRequestsContent> createState() =>
      _EmployeeRequestsContentState();
}

class _EmployeeRequestsContentState extends State<EmployeeRequestsContent>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  bool _submitting = false;

  String? _error;

  List<_EmployeeRequest> _requests = [];

  String _selectedFilter = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ============================================================
  // HELPERS
  // ============================================================

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is! Map) {
      return {};
    }

    final result = <String, dynamic>{};

    raw.forEach((key, value) {
      result[key.toString()] = value;
    });

    return result;
  }

  int _intValue(dynamic raw) {
    if (raw is num) {
      return raw.toInt();
    }

    return int.tryParse(
          raw?.toString() ?? '',
        ) ??
        0;
  }

  String _timeValue(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> _load() async {
    final code = widget.employeeCode.trim().toUpperCase();

    if (code.isEmpty) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'تعذر تحديد كود الموظف.';
      });

      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final snapshot = await FirebaseDatabase.instance
          .ref(
            'employee_requests/$code',
          )
          .limitToLast(100)
          .get();

      final items = <_EmployeeRequest>[];

      if (snapshot.exists && snapshot.value is Map) {
        final data = _asMap(
          snapshot.value,
        );

        for (final entry in data.entries) {
          final value = _asMap(
            entry.value,
          );

          items.add(
            _EmployeeRequest(
              id: entry.key,
              type: value['type']?.toString() ?? '',
              title: value['title']?.toString() ?? '',
              reason: value['reason']?.toString() ?? '',
              date: value['date']?.toString() ?? '',
              fromTime: value['from_time']?.toString() ?? '',
              toTime: value['to_time']?.toString() ?? '',
              status: value['status']?.toString() ?? 'pending',
              createdAt: _intValue(
                value['created_at'],
              ),
              updatedAt: _intValue(
                value['updated_at'],
              ),
              source: value['source']?.toString() ?? 'employee',
              requestedMinutes: _intValue(
                value['requested_minutes'],
              ),
              adminNote: value['admin_note']?.toString() ?? '',
            ),
          );
        }
      }

      items.sort(
        (a, b) => b.createdAt.compareTo(
          a.createdAt,
        ),
      );

      if (!mounted) return;

      setState(() {
        _requests = items;
        _loading = false;
      });
    } on FirebaseException catch (error) {
      debugPrint(
        'Requests Firebase error: '
        '${error.code} ${error.message}',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;

        _error = error.code == 'permission-denied'
            ? 'صلاحية الطلبات غير مفعلة في Firebase.'
            : 'تعذر تحميل الطلبات.';
      });
    } catch (error) {
      debugPrint(
        'Requests error: $error',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'تعذر تحميل الطلبات.';
      });
    }
  }

  // ============================================================
  // FILTER
  // ============================================================

  List<_EmployeeRequest> get _filteredRequests {
    if (_selectedFilter == 'all') {
      return _requests;
    }

    if (_selectedFilter == 'pending') {
      return _requests
          .where(
            (item) => item.status == 'pending',
          )
          .toList();
    }

    if (_selectedFilter == 'approved') {
      return _requests
          .where(
            (item) => item.status == 'approved' || item.status == 'accepted',
          )
          .toList();
    }

    if (_selectedFilter == 'rejected') {
      return _requests
          .where(
            (item) => item.status == 'rejected',
          )
          .toList();
    }

    return _requests;
  }

  int get _pendingCount {
    return _requests
        .where(
          (item) => item.status == 'pending',
        )
        .length;
  }

  int get _approvedCount {
    return _requests
        .where(
          (item) => item.status == 'approved' || item.status == 'accepted',
        )
        .length;
  }

  int get _rejectedCount {
    return _requests
        .where(
          (item) => item.status == 'rejected',
        )
        .length;
  }

  // ============================================================
  // CREATE REQUEST
  // ============================================================

  Future<void> _createRequest() async {
    if (_submitting) return;

    FocusScope.of(context).unfocus();

    final type = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(
        .32,
      ),
      builder: (sheetContext) {
        return const _RequestTypeSheet();
      },
    );

    if (!mounted || type == null) {
      return;
    }

    await _showRequestForm(
      type,
    );
  }

  // ============================================================
  // REQUEST FORM
  // ============================================================

  Future<void> _showRequestForm(
    String type,
  ) async {
    DateTime selectedDate = DateTime.now();

    TimeOfDay? fromTime;
    TimeOfDay? toTime;

    String reason = '';

    late String title;
    late String subtitle;
    late IconData icon;

    switch (type) {
      case 'leave':
        title = 'طلب إجازة';
        subtitle = 'حدد يوم الإجازة واكتب السبب';
        icon = Icons.beach_access_outlined;
        break;

      case 'permission':
        title = 'طلب إذن';
        subtitle = 'حدد وقت الإذن والسبب';
        icon = Icons.schedule_outlined;
        break;

      default:
        title = 'تصحيح حضور';
        subtitle = 'أرسل طلب تعديل الحضور أو الانصراف';
        icon = Icons.edit_calendar_outlined;
    }

    final draft = await showModalBottomSheet<_RequestDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(
        .35,
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (
            context,
            setSheetState,
          ) {
            String formatTime(
              TimeOfDay? value,
            ) {
              if (value == null) {
                return 'اختيار';
              }

              return value.format(
                context,
              );
            }

            return AnimatedPadding(
              duration: const Duration(
                milliseconds: 180,
              ),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(
                  context,
                ).viewInsets.bottom,
              ),
              child: Container(
                margin: const EdgeInsets.fromLTRB(
                  10,
                  10,
                  10,
                  10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(
                    28,
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      18,
                      12,
                      18,
                      19,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.border,
                              borderRadius: BorderRadius.circular(
                                20,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 18,
                        ),
                        Row(
                          children: [
                            Container(
                              width: 45,
                              height: 45,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(
                                  .07,
                                ),
                                borderRadius: BorderRadius.circular(
                                  14,
                                ),
                              ),
                              child: Icon(
                                icon,
                                size: 21,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(
                              width: 11,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 2,
                                  ),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(
                                      fontSize: 8.5,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 21,
                        ),
                        const _FieldLabel(
                          text: 'التاريخ',
                        ),
                        const SizedBox(
                          height: 7,
                        ),
                        _RequestFormField(
                          icon: Icons.calendar_month_outlined,
                          value: DateFormat(
                            'EEEE، d MMMM yyyy',
                            'ar',
                          ).format(
                            selectedDate,
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime.now().subtract(
                                const Duration(
                                  days: 30,
                                ),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(
                                  days: 365,
                                ),
                              ),
                            );

                            if (picked == null) {
                              return;
                            }

                            setSheetState(
                              () {
                                selectedDate = picked;
                              },
                            );
                          },
                        ),
                        if (type != 'leave') ...[
                          const SizedBox(
                            height: 15,
                          ),
                          const _FieldLabel(
                            text: 'الوقت',
                          ),
                          const SizedBox(
                            height: 7,
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: _RequestFormField(
                                  icon: Icons.schedule_rounded,
                                  smallLabel: 'من',
                                  value: formatTime(
                                    fromTime,
                                  ),
                                  onTap: () async {
                                    final picked = await showTimePicker(
                                      context: context,
                                      initialTime: fromTime ?? TimeOfDay.now(),
                                    );

                                    if (picked == null) {
                                      return;
                                    }

                                    setSheetState(
                                      () {
                                        fromTime = picked;
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(
                                width: 8,
                              ),
                              Expanded(
                                child: _RequestFormField(
                                  icon: Icons.schedule_outlined,
                                  smallLabel: 'إلى',
                                  value: formatTime(
                                    toTime,
                                  ),
                                  onTap: () async {
                                    final picked = await showTimePicker(
                                      context: context,
                                      initialTime: toTime ?? TimeOfDay.now(),
                                    );

                                    if (picked == null) {
                                      return;
                                    }

                                    setSheetState(
                                      () {
                                        toTime = picked;
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(
                          height: 15,
                        ),
                        _FieldLabel(
                          text: type == 'correction'
                              ? 'التصحيح المطلوب'
                              : 'سبب الطلب',
                        ),
                        const SizedBox(
                          height: 7,
                        ),

                        /*
                         * لا نستخدم TextEditingController هنا.
                         *
                         * ده يحل مشكلة:
                         * A TextEditingController was used
                         * after being disposed.
                         */
                        TextFormField(
                          initialValue: reason,
                          maxLines: 4,
                          minLines: 3,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          onChanged: (value) {
                            reason = value;
                          },
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.45,
                            color: AppColors.navy,
                          ),
                          decoration: InputDecoration(
                            hintText: type == 'correction'
                                ? 'مثال: تم تسجيل الانصراف بالخطأ وأحتاج تعديل الوقت...'
                                : 'اكتب سبب الطلب باختصار...',
                            hintStyle: const TextStyle(
                              fontSize: 9.5,
                              height: 1.4,
                              color: AppColors.textSecondary,
                            ),
                            filled: true,
                            fillColor: const Color(
                              0xFFF7F9FC,
                            ),
                            contentPadding: const EdgeInsets.all(
                              14,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                15,
                              ),
                              borderSide: BorderSide(
                                color: AppColors.border.withOpacity(
                                  .7,
                                ),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                15,
                              ),
                              borderSide: BorderSide(
                                color: AppColors.primary.withOpacity(
                                  .65,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 18,
                        ),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () {
                              final cleanReason = reason.trim();

                              if (cleanReason.isEmpty) {
                                _showSheetMessage(
                                  context,
                                  'اكتب سبب الطلب أولًا.',
                                );

                                return;
                              }

                              if (type != 'leave' &&
                                  (fromTime == null || toTime == null)) {
                                _showSheetMessage(
                                  context,
                                  'حدد الوقت من وإلى.',
                                );

                                return;
                              }

                              if (fromTime != null && toTime != null) {
                                final from =
                                    fromTime!.hour * 60 + fromTime!.minute;

                                final to = toTime!.hour * 60 + toTime!.minute;

                                if (to <= from) {
                                  _showSheetMessage(
                                    context,
                                    'وقت النهاية لازم يكون بعد وقت البداية.',
                                  );

                                  return;
                                }
                              }

                              Navigator.of(
                                sheetContext,
                              ).pop(
                                _RequestDraft(
                                  type: type,
                                  title: title,
                                  reason: cleanReason,
                                  date: DateFormat(
                                    'yyyy-MM-dd',
                                  ).format(
                                    selectedDate,
                                  ),
                                  fromTime: fromTime == null
                                      ? ''
                                      : _timeValue(
                                          fromTime!,
                                        ),
                                  toTime: toTime == null
                                      ? ''
                                      : _timeValue(
                                          toTime!,
                                        ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  15,
                                ),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.send_rounded,
                                  size: 16,
                                ),
                                SizedBox(
                                  width: 7,
                                ),
                                Text(
                                  'إرسال الطلب',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || draft == null) {
      return;
    }

    await _submit(
      draft,
    );
  }

  void _showSheetMessage(
    BuildContext context,
    String message,
  ) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            message,
          ),
        ),
      );
  }

  // ============================================================
  // SUBMIT
  // ============================================================

  Future<void> _submit(
    _RequestDraft draft,
  ) async {
    if (_submitting) return;

    if (!mounted) return;

    setState(() {
      _submitting = true;
    });

    try {
      final code = widget.employeeCode.trim().toUpperCase();

      if (code.isEmpty) {
        throw Exception(
          'EMPTY_EMPLOYEE_CODE',
        );
      }

      final requestRef = FirebaseDatabase.instance
          .ref(
            'employee_requests/$code',
          )
          .push();

      final now = DateTime.now().millisecondsSinceEpoch;

      await requestRef.set({
        'employee_key': widget.employeeKey,
        'employee_code': code,
        'employee_name': widget.employeeName.trim(),
        if (widget.employeePhotoUrl.trim().isNotEmpty)
          'employee_photo_url': widget.employeePhotoUrl.trim(),
        'type': draft.type,
        'title': draft.title,
        'reason': draft.reason,
        'date': draft.date,
        if (draft.fromTime.isNotEmpty) 'from_time': draft.fromTime,
        if (draft.toTime.isNotEmpty) 'to_time': draft.toTime,
        'status': 'pending',
        'source': 'employee',
        'created_at': now,
        'updated_at': now,
      });

      if (!mounted) return;

      /*
       * نضيف الطلب محليًا فورًا.
       * المستخدم يشوفه بدون انتظار قراءة Firebase مرة ثانية.
       */

      final newRequest = _EmployeeRequest(
        id: requestRef.key ?? '',
        type: draft.type,
        title: draft.title,
        reason: draft.reason,
        date: draft.date,
        fromTime: draft.fromTime,
        toTime: draft.toTime,
        status: 'pending',
        createdAt: now,
        updatedAt: now,
        source: 'employee',
        requestedMinutes: 0,
        adminNote: '',
      );

      setState(() {
        _requests = [
          newRequest,
          ..._requests,
        ];

        _submitting = false;

        _selectedFilter = 'all';
      });

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'تم إرسال الطلب للإدارة بنجاح',
            ),
          ),
        );
    } on FirebaseException catch (error) {
      debugPrint(
        'Submit request Firebase error: '
        '${error.code} ${error.message}',
      );

      if (!mounted) return;

      setState(() {
        _submitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            error.code == 'permission-denied'
                ? 'صلاحية إرسال الطلبات غير مفعلة.'
                : 'تعذر إرسال الطلب. حاول مرة أخرى.',
          ),
        ),
      );
    } catch (error) {
      debugPrint(
        'Submit request error: $error',
      );

      if (!mounted) return;

      setState(() {
        _submitting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'تعذر إرسال الطلب. حاول مرة أخرى.',
          ),
        ),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Container(
      color: const Color(
        0xFFF7FAFC,
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _buildHeader(),
            ),
            if (!_loading && _error == null)
              SliverToBoxAdapter(
                child: _buildFilters(),
              ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.primary,
                  ),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildError(),
              )
            else if (_filteredRequests.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmpty(),
              )
            else
              SliverPadding(
                /*
                 * 120 bottom padding عشان آخر طلب
                 * ما يدخلش تحت الـ Bottom Navigation.
                 */
                padding: const EdgeInsets.fromLTRB(
                  18,
                  14,
                  18,
                  120,
                ),
                sliver: SliverList.separated(
                  itemCount: _filteredRequests.length,
                  separatorBuilder: (_, __) => const SizedBox(
                    height: 10,
                  ),
                  itemBuilder: (context, index) {
                    final request = _filteredRequests[index];

                    return _RequestCard(
                      item: request,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        21,
        20,
        14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الطلبات',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                        color: AppColors.navy,
                      ),
                    ),
                    SizedBox(
                      height: 3,
                    ),
                    Text(
                      'تابع طلباتك وحالتها مع الإدارة',
                      style: TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _submitting ? null : _createRequest,
                  borderRadius: BorderRadius.circular(
                    14,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(
                      milliseconds: 180,
                    ),
                    height: 43,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                    ),
                    decoration: BoxDecoration(
                      color: _submitting
                          ? AppColors.primary.withOpacity(
                              .55,
                            )
                          : AppColors.primary,
                      borderRadius: BorderRadius.circular(
                        14,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(
                            .13,
                          ),
                          blurRadius: 15,
                          offset: const Offset(
                            0,
                            6,
                          ),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_submitting)
                          const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              color: Colors.white,
                            ),
                          )
                        else
                          const Icon(
                            Icons.add_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        const SizedBox(
                          width: 5,
                        ),
                        const Text(
                          'طلب جديد',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_requests.isNotEmpty) ...[
            const SizedBox(
              height: 18,
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(
                  18,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _RequestSummaryItem(
                      value: '${_requests.length}',
                      label: 'الكل',
                    ),
                  ),
                  const _SummaryDivider(),
                  Expanded(
                    child: _RequestSummaryItem(
                      value: '$_pendingCount',
                      label: 'قيد المراجعة',
                    ),
                  ),
                  const _SummaryDivider(),
                  Expanded(
                    child: _RequestSummaryItem(
                      value: '$_approvedCount',
                      label: 'مقبول',
                    ),
                  ),
                  const _SummaryDivider(),
                  Expanded(
                    child: _RequestSummaryItem(
                      value: '$_rejectedCount',
                      label: 'مرفوض',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // FILTERS
  // ============================================================

  Widget _buildFilters() {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
        ),
        children: [
          _FilterChip(
            title: 'الكل',
            selected: _selectedFilter == 'all',
            onTap: () {
              setState(() {
                _selectedFilter = 'all';
              });
            },
          ),
          _FilterChip(
            title: 'قيد المراجعة',
            selected: _selectedFilter == 'pending',
            onTap: () {
              setState(() {
                _selectedFilter = 'pending';
              });
            },
          ),
          _FilterChip(
            title: 'مقبول',
            selected: _selectedFilter == 'approved',
            onTap: () {
              setState(() {
                _selectedFilter = 'approved';
              });
            },
          ),
          _FilterChip(
            title: 'مرفوض',
            selected: _selectedFilter == 'rejected',
            onTap: () {
              setState(() {
                _selectedFilter = 'rejected';
              });
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EMPTY
  // ============================================================

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 90,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(
                .055,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.description_outlined,
              size: 30,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(
            height: 15,
          ),
          Text(
            _selectedFilter == 'all'
                ? 'لا توجد طلبات حتى الآن'
                : 'لا توجد طلبات بهذه الحالة',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          Text(
            _selectedFilter == 'all'
                ? 'أنشئ أول طلب وسيظهر هنا لمتابعة حالته'
                : 'جرّب اختيار حالة أخرى',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9.5,
              color: AppColors.textSecondary,
            ),
          ),
          if (_selectedFilter == 'all') ...[
            const SizedBox(
              height: 17,
            ),
            OutlinedButton.icon(
              onPressed: _createRequest,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: AppColors.primary.withOpacity(
                    .22,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    13,
                  ),
                ),
              ),
              icon: const Icon(
                Icons.add_rounded,
                size: 17,
              ),
              label: const Text(
                'إنشاء طلب',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // ERROR
  // ============================================================

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 90,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 38,
            color: AppColors.textSecondary,
          ),
          const SizedBox(
            height: 12,
          ),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(
            height: 10,
          ),
          TextButton(
            onPressed: _load,
            child: const Text(
              'إعادة المحاولة',
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// REQUEST TYPE SHEET
// ============================================================

class _RequestTypeSheet extends StatelessWidget {
  const _RequestTypeSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(
          10,
        ),
        padding: const EdgeInsets.fromLTRB(
          18,
          12,
          18,
          19,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(
            28,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(
                  20,
                ),
              ),
            ),
            const SizedBox(
              height: 18,
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'إنشاء طلب جديد',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ),
            const SizedBox(
              height: 3,
            ),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'اختر نوع الطلب الذي تريد إرساله للإدارة',
                style: TextStyle(
                  fontSize: 8.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(
              height: 14,
            ),
            _RequestTypeItem(
              icon: Icons.beach_access_outlined,
              title: 'طلب إجازة',
              subtitle: 'إجازة ليوم محدد',
              onTap: () {
                Navigator.pop(
                  context,
                  'leave',
                );
              },
            ),
            const SizedBox(
              height: 7,
            ),
            _RequestTypeItem(
              icon: Icons.schedule_outlined,
              title: 'طلب إذن',
              subtitle: 'خروج أو تأخير خلال وقت العمل',
              onTap: () {
                Navigator.pop(
                  context,
                  'permission',
                );
              },
            ),
            const SizedBox(
              height: 7,
            ),
            _RequestTypeItem(
              icon: Icons.edit_calendar_outlined,
              title: 'تصحيح حضور',
              subtitle: 'تصحيح بصمة حضور أو انصراف',
              onTap: () {
                Navigator.pop(
                  context,
                  'correction',
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// REQUEST TYPE ITEM
// ============================================================

class _RequestTypeItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RequestTypeItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          15,
        ),
        child: Container(
          padding: const EdgeInsets.all(
            11,
          ),
          decoration: BoxDecoration(
            color: const Color(
              0xFFF8FAFC,
            ),
            borderRadius: BorderRadius.circular(
              15,
            ),
            border: Border.all(
              color: AppColors.border.withOpacity(
                .65,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 41,
                height: 41,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(
                    .065,
                  ),
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(
                width: 11,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(
                      height: 2,
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_left_rounded,
                size: 19,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FORM FIELD
// ============================================================

class _RequestFormField extends StatelessWidget {
  final IconData icon;
  final String value;
  final String? smallLabel;
  final VoidCallback onTap;

  const _RequestFormField({
    required this.icon,
    required this.value,
    required this.onTap,
    this.smallLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          14,
        ),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: const Color(
              0xFFF7F9FC,
            ),
            borderRadius: BorderRadius.circular(
              14,
            ),
            border: Border.all(
              color: AppColors.border.withOpacity(
                .65,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: AppColors.primary,
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (smallLabel != null) ...[
                      Text(
                        smallLabel!,
                        style: const TextStyle(
                          fontSize: 7.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(
                        height: 1,
                      ),
                    ],
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navy,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.expand_more_rounded,
                size: 17,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FIELD LABEL
// ============================================================

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: AppColors.navy,
      ),
    );
  }
}

// ============================================================
// FILTER CHIP
// ============================================================

class _FilterChip extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 7,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(
            20,
          ),
          child: AnimatedContainer(
            duration: const Duration(
              milliseconds: 160,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 13,
            ),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(
                20,
              ),
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : AppColors.border.withOpacity(
                        .7,
                      ),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// REQUEST CARD
// ============================================================

class _RequestCard extends StatelessWidget {
  final _EmployeeRequest item;

  const _RequestCard({
    required this.item,
  });

  String get _statusText {
    switch (item.status) {
      case 'approved':
      case 'accepted':
        return 'مقبول';

      case 'rejected':
        return 'مرفوض';

      default:
        return 'قيد المراجعة';
    }
  }

  Color get _statusColor {
    switch (item.status) {
      case 'approved':
      case 'accepted':
        return AppColors.success;

      case 'rejected':
        return AppColors.error;

      default:
        return const Color(
          0xFFC37A16,
        );
    }
  }

  IconData get _icon {
    switch (item.type) {
      case 'leave':
        return Icons.beach_access_outlined;

      case 'permission':
        return Icons.schedule_outlined;

      case 'correction':
        return Icons.edit_calendar_outlined;

      case 'overtime':
        return Icons.more_time_rounded;

      default:
        return Icons.description_outlined;
    }
  }

  String get _typeName {
    switch (item.type) {
      case 'leave':
        return 'إجازة';

      case 'permission':
        return 'إذن';

      case 'correction':
        return 'تصحيح حضور';

      case 'overtime':
        return 'وقت إضافي';

      default:
        return 'طلب';
    }
  }

  String _createdAtText() {
    if (item.createdAt <= 0) {
      return '';
    }

    final date = DateTime.fromMillisecondsSinceEpoch(
      item.createdAt,
    );

    return DateFormat(
      'd MMM • hh:mm a',
      'ar',
    ).format(date);
  }

  @override
  Widget build(BuildContext context) {
    final details = <String>[];

    if (item.date.isNotEmpty) {
      final parsed = DateTime.tryParse(
        item.date,
      );

      if (parsed != null) {
        details.add(
          DateFormat(
            'd MMMM yyyy',
            'ar',
          ).format(parsed),
        );
      } else {
        details.add(
          item.date,
        );
      }
    }

    if (item.fromTime.isNotEmpty && item.toTime.isNotEmpty) {
      details.add(
        '${item.fromTime} - ${item.toTime}',
      );
    }

    if (item.requestedMinutes > 0) {
      details.add(
        '${item.requestedMinutes} دقيقة',
      );
    }

    return Container(
      padding: const EdgeInsets.all(
        14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          18,
        ),
        border: Border.all(
          color: AppColors.border.withOpacity(
            .68,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(
              .025,
            ),
            blurRadius: 18,
            offset: const Offset(
              0,
              6,
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(
                    .06,
                  ),
                  borderRadius: BorderRadius.circular(
                    13,
                  ),
                ),
                child: Icon(
                  _icon,
                  size: 19,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(
                width: 11,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isNotEmpty ? item.title : _typeName,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      item.source == 'admin' ? 'من الإدارة' : 'طلب موظف',
                      style: const TextStyle(
                        fontSize: 7.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(
                    .075,
                  ),
                  borderRadius: BorderRadius.circular(
                    20,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: _statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(
                      width: 5,
                    ),
                    Text(
                      _statusText,
                      style: TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.w700,
                        color: _statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(
              height: 13,
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: const Color(
                  0xFFF8FAFC,
                ),
                borderRadius: BorderRadius.circular(
                  11,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.event_outlined,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(
                    width: 6,
                  ),
                  Expanded(
                    child: Text(
                      details.join(
                        '  •  ',
                      ),
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (item.reason.isNotEmpty) ...[
            const SizedBox(
              height: 11,
            ),
            Text(
              'السبب',
              style: TextStyle(
                fontSize: 7.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary.withOpacity(
                  .85,
                ),
              ),
            ),
            const SizedBox(
              height: 3,
            ),
            Text(
              item.reason,
              style: const TextStyle(
                fontSize: 9.5,
                height: 1.5,
                color: AppColors.navy,
              ),
            ),
          ],
          if (item.adminNote.isNotEmpty) ...[
            const SizedBox(
              height: 10,
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(
                10,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(
                  .045,
                ),
                borderRadius: BorderRadius.circular(
                  10,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(
                    width: 6,
                  ),
                  Expanded(
                    child: Text(
                      item.adminNote,
                      style: const TextStyle(
                        fontSize: 8.5,
                        height: 1.4,
                        color: AppColors.navy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(
            height: 11,
          ),
          Row(
            children: [
              Text(
                '#${item.id.length > 6 ? item.id.substring(item.id.length - 6) : item.id}',
                style: const TextStyle(
                  fontSize: 7,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              if (_createdAtText().isNotEmpty)
                Text(
                  _createdAtText(),
                  style: const TextStyle(
                    fontSize: 7,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SUMMARY ITEM
// ============================================================

class _RequestSummaryItem extends StatelessWidget {
  final String value;
  final String label;

  const _RequestSummaryItem({
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(
          height: 2,
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 7,
              color: Colors.white.withOpacity(
                .58,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 26,
      color: Colors.white.withOpacity(
        .11,
      ),
    );
  }
}

// ============================================================
// MODEL
// ============================================================

class _EmployeeRequest {
  final String id;

  final String type;
  final String title;
  final String reason;

  final String date;

  final String fromTime;
  final String toTime;

  final String status;

  final int createdAt;
  final int updatedAt;

  final String source;

  final int requestedMinutes;

  final String adminNote;

  const _EmployeeRequest({
    required this.id,
    required this.type,
    required this.title,
    required this.reason,
    required this.date,
    required this.fromTime,
    required this.toTime,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
    required this.requestedMinutes,
    required this.adminNote,
  });
}

// ============================================================
// DRAFT
// ============================================================

class _RequestDraft {
  final String type;

  final String title;

  final String reason;

  final String date;

  final String fromTime;
  final String toTime;

  const _RequestDraft({
    required this.type,
    required this.title,
    required this.reason,
    required this.date,
    required this.fromTime,
    required this.toTime,
  });
}
