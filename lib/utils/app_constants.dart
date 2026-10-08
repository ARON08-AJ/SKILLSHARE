class AppConstants {
  // User Roles - DEPRECATED: Use UserRoles class instead
  // Keeping for backward compatibility only
  static const String roleSkilledUser =
      'skilled_person'; // Changed to match UserRoles
  static const String roleCustomer = 'customer';
  static const String roleCompany = 'company';
  static const String roleAdmin = 'admin';
  static const String roleDeliveryPartner = 'delivery_partner';

  // Verification Status
  static const String verificationPending = 'pending';
  static const String verificationSubmitted = 'submitted';
  static const String verificationApproved = 'approved';
  static const String verificationRejected = 'rejected';

  // Profile Visibility
  static const String visibilityPublic = 'public';
  static const String visibilityPrivate = 'private';

  // Job Status
  static const String jobStatusOpen = 'open';
  static const String jobStatusInProgress = 'in_progress';
  static const String jobStatusCompleted = 'completed';
  static const String jobStatusCancelled = 'cancelled';

  // Request Status
  static const String requestStatusPending = 'pending';
  static const String requestStatusAccepted = 'accepted';
  static const String requestStatusRejected = 'rejected';
  static const String requestStatusCompleted = 'completed';

  // Listing / Product Types
  static const String listingTypeProduct = 'product';
  static const String listingTypeService = 'service';

  // Service Workflow Stages
  static const String serviceStatusRequested = 'requested';
  static const String serviceStatusAccepted = 'accepted';
  static const String serviceStatusRequirementGathering = 'requirement_gathering';
  static const String serviceStatusProjectWork = 'project_work';
  static const String serviceStatusTesting = 'testing';
  static const String serviceStatusReview = 'review';
  static const String serviceStatusFinished = 'finished';
  static const String serviceStatusRejected = 'rejected';
  static const String serviceStatusCancelled = 'cancelled';

  /// Ordered service progression stages after acceptance
  static const List<String> serviceProgressStages = [
    serviceStatusAccepted,
    serviceStatusRequirementGathering,
    serviceStatusProjectWork,
    serviceStatusTesting,
    serviceStatusReview,
    serviceStatusFinished,
  ];

  // Collection Names
  static const String usersCollection = 'users';
  static const String skilledUsersCollection = 'skilled_users';
  static const String customerProfilesCollection = 'customer_profiles';
  static const String companyProfilesCollection = 'company_profiles';
  static const String jobsCollection = 'jobs';
  static const String reviewsCollection = 'reviews';
  static const String chatsCollection = 'chats';
  static const String messagesCollection = 'messages';
  static const String requestsCollection = 'requests';
  static const String appealsCollection = 'appeals';
  static const String productsCollection = 'products';
  static const String aadhaarRegistryCollection = 'aadhaar_registry';
  static const String cartsCollection = 'carts';
  static const String ordersCollection = 'orders';
  static const String reportsCollection = 'reports';
  static const String blockedUsersCollection = 'blocked_users';
  static const String supportTicketsCollection = 'support_tickets';
  static const String deliveryAssignmentsCollection = 'delivery_assignments';
  static const String companyEndorsementsCollection = 'company_endorsements';
  static const String managedMembersCollection = 'managed_members';
  static const String skilledVerificationPrivateCollection =
      'skilled_verification_private';

  // Managed member types
  static const String memberTypeCompany = 'company_member';
  static const String memberTypeSkilled = 'skilled_member';

  // Approval status
  static const String approvalPending = 'pending';
  static const String approvalApproved = 'approved';
  static const String approvalRejected = 'rejected';

  // Storage Paths
  static const String profilePhotosPath = 'profile_photos';
  static const String portfolioPath = 'portfolio';
  static const String productPhotosPath = 'product_photos';
  static const String chatMediaPath = 'chat_media';
  static const String verificationDocsPath = 'verification_documents';

  // Aadhaar Pattern (for validation)
  static const String aadhaarPattern = r'^\d{4}\s\d{4}\s\d{4}$';

  // Max file sizes (in bytes)
  static const int maxImageSize = 5 * 1024 * 1024; // 5MB
  static const int maxVideoSize = 50 * 1024 * 1024; // 50MB

  // Pagination
  static const int itemsPerPage = 20;

  // Location search radius (in kilometers)
  static const double searchRadius = 50.0;

  // Categories for skills/portfolios/products
  static const List<String> categories = [
    'Baking',
    'Carpentry',
    'Plumbing',
    'Electrical',
    'Painting',
    'Tailoring',
    'Handicrafts',
    'Artwork',
    'Beauty Services',
    'Furniture Making',
    'Home Decor',
    'Catering',
    'Photography',
    'Other',
  ];
}
