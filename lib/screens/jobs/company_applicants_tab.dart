import 'package:flutter/material.dart';
import '../../models/job_model.dart';
import '../../models/user_model.dart';
import '../../models/skilled_user_profile.dart';
import '../../services/firestore_service.dart';
import '../../utils/app_dialog.dart';
import '../../utils/app_helpers.dart';
import '../../widgets/universal_avatar.dart';
import '../profile/profile_screen.dart';

// 
// Level 1: list of posted jobs
// 

class CompanyApplicantsTab extends StatelessWidget {
  final List<JobModel> jobs;
  final bool isLoading;

  const CompanyApplicantsTab({
    super.key,
    required this.jobs,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.work_off_outlined, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No posted jobs yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Post a job to start receiving applications.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final job = jobs[index];
        return _JobSummaryCard(job: job);
      },
    );
  }
}

class _JobSummaryCard extends StatelessWidget {
  final JobModel job;
  const _JobSummaryCard({required this.job});

  Color get _statusColor {
    switch (job.status) {
      case 'open':
        return Colors.green;
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return const Color(0xFF1565C0);
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = job.applicants
        .where((id) =>
            (job.applicationStatus[id] ?? 'pending') != 'rejected')
        .length;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobApplicantsScreen(job: job),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.work_outline,
                    color: Color(0xFF2196F3), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            job.status.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _statusColor,
                            ),
                          ),
                        ),
                        Text(
                          'Deadline: ${AppHelpers.formatDate(job.deadline)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: count > 0
                          ? const Color(0xFF4CAF50).withValues(alpha: 0.12)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count ${count == 1 ? "applicant" : "applicants"}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: count > 0
                            ? Colors.green[700]
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right,
                      color: Colors.grey, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 
// Level 2: applicants for one specific job  (no Edit / Share / menu)
// 

class JobApplicantsScreen extends StatefulWidget {
  final JobModel job;
  const JobApplicantsScreen({super.key, required this.job});

  @override
  State<JobApplicantsScreen> createState() => _JobApplicantsScreenState();
}

class _JobApplicantsScreenState extends State<JobApplicantsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late JobModel _job;
  bool _isLoading = true;
  String? _processingId;
  List<_ApplicantEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _job = widget.job;
    _loadApplicants();
  }

  Future<void> _loadApplicants() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // Re-fetch the job so applicants list is always up-to-date
    final freshJob = await _firestoreService.getJobById(_job.id);
    if (freshJob != null && mounted) {
      _job = freshJob;
    }

    final entries = <_ApplicantEntry>[];
    for (final applicantId in _job.applicants) {
      final results = await Future.wait([
        _firestoreService.getUserById(applicantId),
        _firestoreService.getSkilledUserProfile(applicantId),
      ]);
      final user = results[0] as UserModel?;
      var profile = results[1] as SkilledUserProfile?;

      // Fallback: show applicant even without a skilled profile doc
      if (profile == null && user != null) {
        profile = SkilledUserProfile(
          userId: applicantId,
          name: user.name,
          bio: '',
          skills: const [],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
      }

      if (profile != null || user != null) {
        entries.add(_ApplicantEntry(profile: profile, user: user));
      }
    }

    if (!mounted) return;
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _accept(String applicantId) async {
    // ── 1. Check for scheduling conflicts ───────────────────────────────────
    setState(() => _processingId = applicantId);
    String? conflictMsg;
    try {
      conflictMsg = await _firestoreService.checkJobConflicts(
          applicantId, _job.id);
    } catch (_) {
      // Non-fatal: proceed without conflict info if check fails
    }

    if (conflictMsg != null && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Schedule Conflict',
                    style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(conflictMsg!,
                  style: const TextStyle(fontSize: 14, height: 1.5)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'You can still proceed — the applicant will be notified '
                  'and can choose to accept or decline your offer.',
                  style: TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Proceed Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) {
        setState(() => _processingId = null);
        return;
      }
    }

    // ── 2. Accept ────────────────────────────────────────────────────────────
    try {
      await _firestoreService.acceptJobApplicant(
        jobId: _job.id,
        applicantId: applicantId,
        companyId: _job.companyId,
      );
      if (mounted) {
        AppDialog.success(context,
            'Applicant accepted! Offer letter sent in dedicated job chat.');
      }
    } catch (e) {
      if (mounted) AppDialog.error(context, 'Failed', detail: e.toString());
    } finally {
      if (mounted) setState(() => _processingId = null);
      await _loadApplicants();
    }
  }

  Future<void> _reject(String applicantId) async {
    setState(() => _processingId = applicantId);
    try {
      await _firestoreService.rejectJobApplicant(
        jobId: _job.id,
        applicantId: applicantId,
        companyId: _job.companyId,
      );
      if (mounted) AppDialog.success(context, 'Applicant rejected.');
    } catch (e) {
      if (mounted) AppDialog.error(context, 'Failed', detail: e.toString());
    } finally {
      if (mounted) setState(() => _processingId = null);
      await _loadApplicants();
    }
  }

  Future<void> _revoke(String applicantId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Revoke Acceptance',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to revoke the accepted offer for $displayName?\n\n'
          'They will be notified and the job will be re-opened.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _processingId = applicantId);
    try {
      await _firestoreService.rejectJobApplicant(
        jobId: _job.id,
        applicantId: applicantId,
        companyId: _job.companyId,
      );
      if (mounted) AppDialog.success(context, 'Acceptance revoked. Job is re-opened.');
    } catch (e) {
      if (mounted) AppDialog.error(context, 'Failed', detail: e.toString());
    } finally {
      if (mounted) setState(() => _processingId = null);
      await _loadApplicants();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _job.title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2196F3), Color(0xFF00BCD4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        // No actions: no Edit, Share, or kebab menu
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline,
                          size: 72, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No applications yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Skilled users who apply for this job appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadApplicants,
                  color: const Color(0xFF2196F3),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _buildApplicantCard(_entries[index]),
                  ),
                ),
    );
  }

  Widget _buildApplicantCard(_ApplicantEntry entry) {
    final status = _job.applicationStatus[entry.userId] ?? 'pending';
    final isAccepted = status == 'accepted';
    final isRejected = status == 'rejected';
    final isPending = !isAccepted && !isRejected;
    final isProcessing = _processingId == entry.userId;
    final anotherSelected = _job.selectedApplicant != null &&
        _job.selectedApplicant!.isNotEmpty &&
        _job.selectedApplicant != entry.userId;

    return Card(
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            InkWell(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => ProfileScreen(userId: entry.userId)),
              ),
              borderRadius: BorderRadius.circular(26),
              child: UniversalAvatar(
                avatarConfig: entry.user?.avatarConfig,
                photoUrl: entry.profile?.profilePicture,
                fallbackName: entry.displayName,
                radius: 26,
                animate: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ProfileScreen(userId: entry.userId)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.profile?.isVerified == true) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified,
                              color: Colors.blue, size: 16),
                        ],
                      ],
                    ),
                    if ((entry.profile?.category ?? '').isNotEmpty)
                      Text(
                        entry.profile!.category!,
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 13),
                      ),
                    if ((entry.profile?.rating ?? 0) > 0) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star,
                              color: Colors.amber, size: 13),
                          const SizedBox(width: 3),
                          Text(
                            '${entry.profile!.rating.toStringAsFixed(1)} (${entry.profile!.reviewCount})',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isAccepted
                            ? Colors.green.withValues(alpha: 0.12)
                            : isRejected
                                ? Colors.red.withValues(alpha: 0.12)
                                : Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isAccepted
                            ? 'Accepted'
                            : isRejected
                                ? 'Rejected'
                                : 'Pending',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isAccepted
                              ? Colors.green[700]
                              : isRejected
                                  ? Colors.red[700]
                                  : Colors.orange[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isPending && !anotherSelected)
              isProcessing
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 32,
                          child: TextButton(
                            onPressed: () => _reject(entry.userId),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10),
                              minimumSize: Size.zero,
                            ),
                            child: const Text(
                              'Reject',
                              style:
                                  TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 32,
                          child: ElevatedButton(
                            onPressed: () => _accept(entry.userId),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              minimumSize: Size.zero,
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            child: const Text('Accept'),
                          ),
                        ),
                      ],
                    )
            else if (isAccepted)
              isProcessing
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 24),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 28,
                          child: TextButton(
                            onPressed: () =>
                                _revoke(entry.userId, entry.displayName),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Revoke',
                              style: TextStyle(
                                  color: Colors.red, fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    )
            else if (isRejected)
              const Icon(Icons.cancel, color: Colors.red, size: 28),
          ],
        ),
      ),
    );
  }
}

// 
// Helper data class
// 

class _ApplicantEntry {
  final SkilledUserProfile? profile;
  final UserModel? user;

  _ApplicantEntry({this.profile, this.user});

  String get userId => user?.uid ?? profile?.userId ?? '';

  String get displayName {
    if (user?.name.trim().isNotEmpty == true) return user!.name.trim();
    if (profile?.name?.trim().isNotEmpty == true) return profile!.name!.trim();
    return 'Unknown';
  }
}
