import FeatureCore
import Farm
import Finance
import FrontOffice
import League
import MajorLeague
import Medical
import Philosophy
import Scouting
import Trades

/// The app's departments (SWIFTUI_REBUILD.md section 6): the app target assembles the registry from the department
/// modules; the sidebar, the Go menu and (later) search come from it. Adding a department means adding its module
/// here; adding a view means adding a descriptor to its module.
enum AppRegistry {
    static let shared: DepartmentRegistry = {
        let registry = DepartmentRegistry([
            FrontOfficeDepartment.self,
            MajorLeagueDepartment.self,
            FarmDepartment.self,
            ScoutingDepartment.self,
            TradesDepartment.self,
            FinanceDepartment.self,
            MedicalDepartment.self,
            LeagueDepartment.self,
            PhilosophyDepartment.self,
        ])
        assert(registry.problems.isEmpty, "The department registry is unsound: \(registry.problems)")
        return registry
    }()
}
