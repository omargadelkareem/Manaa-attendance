import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';

class AttendanceHistoryContent extends StatefulWidget {
  final String employeeCode;
  final String employeeName;

  const AttendanceHistoryContent({
    super.key,
    required this.employeeCode,
    required this.employeeName,
  });

  @override
  State<AttendanceHistoryContent> createState() =>
      _AttendanceHistoryContentState();
}

class _AttendanceHistoryContentState extends State<AttendanceHistoryContent>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;

  List<_AttendanceDay> _records = [];

  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
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

  int? _timestamp(dynamic raw) {
    if (raw == null) {
      return null;
    }

    if (raw is num) {
      return raw.toInt();
    }

    if (raw is Map) {
      final map = _asMap(raw);

      final candidates = [
        map['timestamp'],
        map['created_at'],
        map['time'],
        map['at'],
      ];

      for (final value in candidates) {
        if (value is num) {
          return value.toInt();
        }

        final parsed = int.tryParse(
          value?.toString() ?? '',
        );

        if (parsed != null) {
          return parsed;
        }
      }
    }

    return int.tryParse(
      raw.toString(),
    );
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

  // ============================================================
  // LOAD ATTENDANCE
  // ============================================================

  Future<void> _loadAttendance() async {
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
      /*
       * Firebase structure:
       *
       * attendance_records
       *   2026-10-03
       *      EMP001
       *        check_in
       *        check_out
       *
       * نقرأ الشهر المحدد فقط بدل تحميل تاريخ الشركة كله.
       */

      final daysInMonth = DateUtils.getDaysInMonth(
        _selectedYear,
        _selectedMonth,
      );

      final futures = <Future<_AttendanceDay?>>[];

      for (int day = 1; day <= daysInMonth; day++) {
        final date = DateTime(
          _selectedYear,
          _selectedMonth,
          day,
        );

        final dateKey = DateFormat(
          'yyyy-MM-dd',
        ).format(date);

        futures.add(
          _readAttendanceDay(
            dateKey,
            code,
          ),
        );
      }

      final results = await Future.wait(
        futures,
      );

      final records = results.whereType<_AttendanceDay>().toList();

      records.sort(
        (a, b) => b.date.compareTo(a.date),
      );

      if (!mounted) return;

      setState(() {
        _records = records;
        _loading = false;
      });
    } on FirebaseException catch (error) {
      debugPrint(
        'Attendance history Firebase error: '
        '${error.code} ${error.message}',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;

        _error = error.code == 'permission-denied'
            ? 'لا توجد صلاحية لقراءة سجل الحضور.'
            : 'تعذر تحميل سجل الحضور.';
      });
    } catch (error) {
      debugPrint(
        'Attendance history error: $error',
      );

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'تعذر تحميل سجل الحضور.';
      });
    }
  }

  Future<_AttendanceDay?> _readAttendanceDay(
    String dateKey,
    String employeeCode,
  ) async {
    final snapshot = await FirebaseDatabase.instance
        .ref(
          'attendance_records/'
          '$dateKey/'
          '$employeeCode',
        )
        .get();

    if (!snapshot.exists || snapshot.value == null) {
      return null;
    }

    final data = _asMap(
      snapshot.value,
    );

    if (data.isEmpty) {
      return null;
    }

    final checkInData = _asMap(
      data['check_in'],
    );

    final checkOutData = _asMap(
      data['check_out'],
    );

    final breakData = _asMap(
      data['break'],
    );

    final checkInTimestamp = _timestamp(
      data['check_in'],
    );

    final checkOutTimestamp = _timestamp(
      data['check_out'],
    );

    final breakStartTimestamp = _timestamp(
      breakData['start'],
    );

    final breakEndTimestamp = _timestamp(
      breakData['end'],
    );

    final breakMinutes = _intValue(
      breakData['duration_minutes'],
    );

    final date = DateTime.tryParse(
          dateKey,
        ) ??
        DateTime.now();

    return _AttendanceDay(
      dateKey: dateKey,
      date: date,
      checkInTimestamp: checkInTimestamp,
      checkOutTimestamp: checkOutTimestamp,
      breakStartTimestamp: breakStartTimestamp,
      breakEndTimestamp: breakEndTimestamp,
      breakMinutes: breakMinutes,
      status: data['status']?.toString() ?? '',
      checkInLatitude: _doubleValue(
        checkInData['latitude'],
      ),
      checkInLongitude: _doubleValue(
        checkInData['longitude'],
      ),
      faceVerified: checkInData['face_identity_verified'] == true,
    );
  }

  double? _doubleValue(dynamic raw) {
    if (raw is num) {
      return raw.toDouble();
    }

    return double.tryParse(
      raw?.toString() ?? '',
    );
  }

  // ============================================================
  // MONTH
  // ============================================================

  Future<void> _previousMonth() async {
    var month = _selectedMonth - 1;
    var year = _selectedYear;

    if (month == 0) {
      month = 12;
      year--;
    }

    setState(() {
      _selectedMonth = month;
      _selectedYear = year;
    });

    await _loadAttendance();
  }

  Future<void> _nextMonth() async {
    final now = DateTime.now();

    var month = _selectedMonth + 1;
    var year = _selectedYear;

    if (month == 13) {
      month = 1;
      year++;
    }

    final target = DateTime(
      year,
      month,
    );

    final current = DateTime(
      now.year,
      now.month,
    );

    if (target.isAfter(current)) {
      return;
    }

    setState(() {
      _selectedMonth = month;
      _selectedYear = year;
    });

    await _loadAttendance();
  }

  bool get _canGoNext {
    final now = DateTime.now();

    return !(_selectedMonth == now.month && _selectedYear == now.year);
  }

  // ============================================================
  // FORMAT
  // ============================================================

  String _time(int? timestamp) {
    if (timestamp == null) {
      return '--:--';
    }

    return DateFormat(
      'hh:mm a',
      'ar',
    ).format(
      DateTime.fromMillisecondsSinceEpoch(
        timestamp,
      ),
    );
  }

  String _dayName(DateTime date) {
    return DateFormat(
      'EEEE',
      'ar',
    ).format(date);
  }

  String _dateNumber(DateTime date) {
    return DateFormat(
      'd MMMM',
      'ar',
    ).format(date);
  }

  String _monthTitle() {
    return DateFormat(
      'MMMM yyyy',
      'ar',
    ).format(
      DateTime(
        _selectedYear,
        _selectedMonth,
      ),
    );
  }

  // ============================================================
  // WORK DURATION
  // ============================================================

  int _workMinutes(
    _AttendanceDay record,
  ) {
    if (record.checkInTimestamp == null || record.checkOutTimestamp == null) {
      return 0;
    }

    var minutes =
        ((record.checkOutTimestamp! - record.checkInTimestamp!) / 60000)
            .floor();

    minutes -= record.breakMinutes;

    if (minutes < 0) {
      minutes = 0;
    }

    return minutes;
  }

  String _workDuration(
    _AttendanceDay record,
  ) {
    if (record.checkInTimestamp == null || record.checkOutTimestamp == null) {
      return '--';
    }

    final minutes = _workMinutes(
      record,
    );

    final hours = minutes ~/ 60;
    final rest = minutes % 60;

    if (hours == 0) {
      return '$rest د';
    }

    if (rest == 0) {
      return '$hours س';
    }

    return '$hours س $rest د';
  }

  // ============================================================
  // SUMMARY
  // ============================================================

  int get _attendanceDays {
    return _records
        .where(
          (record) => record.checkInTimestamp != null,
        )
        .length;
  }

  int get _completedDays {
    return _records
        .where(
          (record) =>
              record.checkInTimestamp != null &&
              record.checkOutTimestamp != null,
        )
        .length;
  }

  int get _totalWorkMinutes {
    return _records.fold(
      0,
      (total, record) => total + _workMinutes(record),
    );
  }

  String get _totalWorkText {
    final minutes = _totalWorkMinutes;

    final hours = minutes ~/ 60;
    final rest = minutes % 60;

    if (hours == 0) {
      return '$rest د';
    }

    if (rest == 0) {
      return '$hours س';
    }

    return '$hours س $rest د';
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
        onRefresh: _loadAttendance,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: _buildHeader(),
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
            else if (_records.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmpty(),
              )
            else ...[
              SliverToBoxAdapter(
                child: _buildSummary(),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  120,
                ),
                sliver: SliverList.separated(
                  itemCount: _records.length,
                  separatorBuilder: (_, __) => const SizedBox(
                    height: 11,
                  ),
                  itemBuilder: (context, index) {
                    return _AttendanceCard(
                      record: _records[index],
                      timeFormatter: _time,
                      workDuration: _workDuration(
                        _records[index],
                      ),
                      dayName: _dayName(
                        _records[index].date,
                      ),
                      dateNumber: _dateNumber(
                        _records[index].date,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        20,
        21,
        20,
        17,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'سجل الحضور',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            widget.employeeName.trim().isEmpty
                ? 'تفاصيل حضورك وانصرافك'
                : 'تفاصيل حضور ${widget.employeeName.trim()}',
            style: const TextStyle(
              fontSize: 9.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(
            height: 19,
          ),
          Container(
            height: 51,
            padding: const EdgeInsets.symmetric(
              horizontal: 7,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(
                16,
              ),
              border: Border.all(
                color: AppColors.border.withOpacity(.72),
              ),
            ),
            child: Row(
              children: [
                _MonthButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: _previousMonth,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'الفترة',
                        style: TextStyle(
                          fontSize: 7.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(
                        height: 2,
                      ),
                      Text(
                        _monthTitle(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                ),
                _MonthButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: _canGoNext ? _nextMonth : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUMMARY
  // ============================================================

  Widget _buildSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(
            19,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withOpacity(.08),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _SummaryItem(
                value: '$_attendanceDays',
                title: 'أيام الحضور',
              ),
            ),
            const _SummaryDivider(),
            Expanded(
              child: _SummaryItem(
                value: '$_completedDays',
                title: 'أيام مكتملة',
              ),
            ),
            const _SummaryDivider(),
            Expanded(
              child: _SummaryItem(
                value: _totalWorkText,
                title: 'إجمالي العمل',
              ),
            ),
          ],
        ),
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
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(.055),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_month_outlined,
              size: 29,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(
            height: 15,
          ),
          const Text(
            'لا يوجد حضور في هذا الشهر',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(
            height: 5,
          ),
          const Text(
            'أي بصمة حضور أو انصراف ستظهر هنا تلقائيًا',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9.5,
              color: AppColors.textSecondary,
            ),
          ),
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
            onPressed: _loadAttendance,
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
// ATTENDANCE CARD
// ============================================================

class _AttendanceCard extends StatelessWidget {
  final _AttendanceDay record;

  final String Function(int?) timeFormatter;

  final String workDuration;

  final String dayName;
  final String dateNumber;

  const _AttendanceCard({
    required this.record,
    required this.timeFormatter,
    required this.workDuration,
    required this.dayName,
    required this.dateNumber,
  });

  @override
  Widget build(BuildContext context) {
    final completed = record.checkOutTimestamp != null;

    final working = record.checkInTimestamp != null && !completed;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          19,
        ),
        border: Border.all(
          color: AppColors.border.withOpacity(.68),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(.025),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              14,
              13,
              14,
              12,
            ),
            child: Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(.06),
                    borderRadius: BorderRadius.circular(
                      13,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        record.date.day.toString(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      Text(
                        DateFormat(
                          'MMM',
                          'ar',
                        ).format(
                          record.date,
                        ),
                        style: const TextStyle(
                          fontSize: 7,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
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
                        dayName,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(
                        height: 2,
                      ),
                      Text(
                        dateNumber,
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(
                  working: working,
                  completed: completed,
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(
              horizontal: 14,
            ),
            color: AppColors.border.withOpacity(.55),
          ),
          Padding(
            padding: const EdgeInsets.all(
              14,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _AttendanceValue(
                    icon: Icons.login_rounded,
                    title: 'الحضور',
                    value: timeFormatter(
                      record.checkInTimestamp,
                    ),
                    color: AppColors.success,
                  ),
                ),
                _ValueDivider(),
                Expanded(
                  child: _AttendanceValue(
                    icon: Icons.logout_rounded,
                    title: 'الانصراف',
                    value: timeFormatter(
                      record.checkOutTimestamp,
                    ),
                    color: AppColors.error,
                  ),
                ),
                _ValueDivider(),
                Expanded(
                  child: _AttendanceValue(
                    icon: Icons.coffee_outlined,
                    title: 'الاستراحة',
                    value: record.breakMinutes > 0
                        ? '${record.breakMinutes} د'
                        : '--',
                    color: const Color(
                      0xFFE28B18,
                    ),
                  ),
                ),
                _ValueDivider(),
                Expanded(
                  child: _AttendanceValue(
                    icon: Icons.schedule_rounded,
                    title: 'صافي العمل',
                    value: workDuration,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          if (record.faceVerified)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(
                14,
                0,
                14,
                13,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(.055),
                borderRadius: BorderRadius.circular(
                  10,
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 14,
                    color: AppColors.success,
                  ),
                  SizedBox(
                    width: 6,
                  ),
                  Text(
                    'تم التحقق من الهوية بالوجه',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// STATUS
// ============================================================

class _StatusBadge extends StatelessWidget {
  final bool working;
  final bool completed;

  const _StatusBadge({
    required this.working,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    late String text;
    late Color color;

    if (completed) {
      text = 'مكتمل';
      color = AppColors.success;
    } else if (working) {
      text = 'على رأس العمل';
      color = AppColors.primary;
    } else {
      text = 'غير مكتمل';
      color = AppColors.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(
          20,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ============================================================
// ATTENDANCE VALUE
// ============================================================

class _AttendanceValue extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _AttendanceValue({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(.065),
            borderRadius: BorderRadius.circular(
              9,
            ),
          ),
          child: Icon(
            icon,
            size: 14,
            color: color,
          ),
        ),
        const SizedBox(
          height: 6,
        ),
        Text(
          title,
          style: const TextStyle(
            fontSize: 7,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(
          height: 2,
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// SUMMARY
// ============================================================

class _SummaryItem extends StatelessWidget {
  final String value;
  final String title;

  const _SummaryItem({
    required this.value,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(
          height: 3,
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 7.5,
            color: Colors.white.withOpacity(.60),
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
      height: 27,
      color: Colors.white.withOpacity(
        .12,
      ),
    );
  }
}

// ============================================================
// MONTH BUTTON
// ============================================================

class _MonthButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _MonthButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(
        11,
      ),
      child: Container(
        width: 37,
        height: 37,
        decoration: BoxDecoration(
          color: onTap == null
              ? Colors.transparent
              : AppColors.primary.withOpacity(.055),
          borderRadius: BorderRadius.circular(
            11,
          ),
        ),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null
              ? AppColors.textSecondary.withOpacity(.25)
              : AppColors.primary,
        ),
      ),
    );
  }
}

// ============================================================
// DIVIDER
// ============================================================

class _ValueDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      color: AppColors.border.withOpacity(.55),
    );
  }
}

// ============================================================
// MODEL
// ============================================================

class _AttendanceDay {
  final String dateKey;
  final DateTime date;

  final int? checkInTimestamp;
  final int? checkOutTimestamp;

  final int? breakStartTimestamp;
  final int? breakEndTimestamp;

  final int breakMinutes;

  final String status;

  final double? checkInLatitude;
  final double? checkInLongitude;

  final bool faceVerified;

  const _AttendanceDay({
    required this.dateKey,
    required this.date,
    required this.checkInTimestamp,
    required this.checkOutTimestamp,
    required this.breakStartTimestamp,
    required this.breakEndTimestamp,
    required this.breakMinutes,
    required this.status,
    required this.checkInLatitude,
    required this.checkInLongitude,
    required this.faceVerified,
  });
}
