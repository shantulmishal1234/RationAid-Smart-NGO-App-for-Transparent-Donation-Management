// Compatibility shim — dashboard_router.dart imports VolunteerDashboard from here.
// The real implementation is DistributorDashboard in screens/Distributor/.
export 'package:ration_aid/screens/Distributor/distributor_dashboard.dart'
    show DistributorDashboard;

// Alias so existing import `VolunteerDashboard` still resolves
import 'package:ration_aid/screens/Distributor/distributor_dashboard.dart';

typedef VolunteerDashboard = DistributorDashboard;
