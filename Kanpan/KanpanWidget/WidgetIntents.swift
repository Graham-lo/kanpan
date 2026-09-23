import AppIntents
import KanpanCore
import WidgetKit

// 两种尺寸各一个编辑项，只此一项：小号选自选分类，中号选一只品种。
// 选项都从快照里来——分类就是自选页上那几类，前面垫一个「全部」。

struct FavoriteGroupEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "自选分类"
  static let defaultQuery = FavoriteGroupQuery()
  static let all = FavoriteGroupEntity(id: WidgetSnapshot.allGroupID, name: WidgetSnapshot.allGroupName)

  var id: String
  var name: String
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct FavoriteGroupQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [FavoriteGroupEntity] {
    let options = Self.options()
    return identifiers.compactMap { id in options.first { $0.id == id } }
  }

  func suggestedEntities() async throws -> [FavoriteGroupEntity] { Self.options() }
  func defaultResult() async -> FavoriteGroupEntity? { .all }

  static func options() -> [FavoriteGroupEntity] {
    [.all] + (SnapshotStore.load()?.groups.map { FavoriteGroupEntity(id: $0.id, name: $0.name) } ?? [])
  }
}

struct FavoritesIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "自选"
  static let description = IntentDescription("自选里的前四只")

  @Parameter(title: "分类")
  var group: FavoriteGroupEntity?

  init() {}
}

struct SymbolEntity: AppEntity {
  static let typeDisplayRepresentation: TypeDisplayRepresentation = "品种"
  static let defaultQuery = SymbolQuery()

  var id: String
  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(Alert.base(of: id))") }
}

struct SymbolQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [SymbolEntity] { identifiers.map { SymbolEntity(id: $0) } }
  func suggestedEntities() async throws -> [SymbolEntity] {
    (SnapshotStore.load()?.favorites ?? []).map { SymbolEntity(id: $0) }
  }
  func defaultResult() async -> SymbolEntity? { SnapshotStore.load()?.favorites.first.map { SymbolEntity(id: $0) } }
}

struct SymbolIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "品种"
  static let description = IntentDescription("一只品种的价与走势")

  @Parameter(title: "品种")
  var symbol: SymbolEntity?

  init() {}
}
