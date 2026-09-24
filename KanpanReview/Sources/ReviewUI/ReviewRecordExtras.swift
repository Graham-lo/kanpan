import SwiftUI
import KanpanCore
import PhotosUI
import UIKit
import ReviewDomain
import ReviewData

// P3.7 复盘交互里三样「打开那一页才去问服务端」的东西：已存案例、修订记录、补图。
// 它们不进本机存档、不排上传队列，状态就留在各自那一页上。

/// 复盘本「…」→「已存案例」：在「找相似」里左滑存下的那些区间。可删，点开回到图上看。
struct ReviewSavedMatchesView: View {
  @Bindable var feature: ReviewFeature
  @Environment(\.reviewTheme) private var t
  @State private var items: [NativeSavedMatch] = []
  @State private var next: String?
  @State private var loaded = false
  @State private var loading = false
  @State private var error: String?
  var body: some View {
    List {
      if !feature.isConnected {
        Text("登录后可用").foregroundStyle(t.ink3).listRowBackground(t.app)
        Button("登录") { feature.bookOpen = false; feature.onLogin() }.listRowBackground(t.app)
      } else {
        ForEach(items) { saved in
          Button { feature.openSavedMatch(saved.item) } label: { row(saved.item) }
            .foregroundStyle(t.ink)
            .listRowBackground(t.app)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              Button(role: .destructive) { Task { await remove(saved) } } label: { Label("删除", systemImage: "trash") }
            }
            .accessibilityIdentifier("review.saved.row")
        }
        if loading { ProgressView().frame(maxWidth: .infinity).listRowBackground(t.app).listRowSeparator(.hidden) }
        if let error {
          Text(error).foregroundStyle(t.ink3).listRowBackground(t.app)
          Button("重试") { Task { await load(reset: items.isEmpty) } }.listRowBackground(t.app)
        }
        if loaded && items.isEmpty && !loading && error == nil {
          Text("还没有存下的案例").foregroundStyle(t.ink3).frame(maxWidth: .infinity, minHeight: 44)
            .listRowBackground(t.app).listRowSeparator(.hidden)
            .accessibilityIdentifier("review.saved.empty")
        }
        if next != nil && error == nil {
          Color.clear.frame(height: 1).listRowBackground(t.app).listRowSeparator(.hidden)
            .onAppear { Task { await load(reset: false) } }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(t.app)
    .readableColumn()
    .navigationTitle("已存案例").navigationBarTitleDisplayMode(.inline)
    .task { await load(reset: true) }
    .refreshable { await load(reset: true) }
  }
  private func row(_ match: ReviewMatch) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 5) {
        Text(match.range.shortSymbol + " · " + Interval.shortLabel(raw: match.range.interval)).fontWeight(.medium).foregroundStyle(t.ink)
        Text(feature.fullTime(match.range.start)).font(.caption).foregroundStyle(t.ink3)
        Text("\(match.range.bars) 根").font(.caption).foregroundStyle(t.ink3)
      }
      Spacer(); Text("相似 " + match.scoreText).monospacedDigit().foregroundStyle(t.ink2)
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(t.ink3)
    }.padding(.vertical, 5)
  }
  private func load(reset: Bool) async {
    guard feature.isConnected, !loading else { return }
    if !reset && next == nil { return }
    loading = true; error = nil
    defer { loading = false }
    do {
      let page = try await feature.savedMatchesPage(after: reset ? nil : next)
      let known = reset ? [] : Set(items.map(\.id))
      items = (reset ? [] : items) + page.items.filter { !known.contains($0.id) }
      next = page.next; loaded = true
    } catch { self.error = error.localizedDescription }
  }
  private func remove(_ saved: NativeSavedMatch) async {
    do {
      try await feature.removeSavedMatch(saved)
      items.removeAll { $0.id == saved.id }
    } catch {
      // 409：别的设备刚重新存过它，版本号变了。拉一遍最新的，人再删一次就是对的那一版。
      self.error = error.localizedDescription
      await load(reset: true)
    }
  }
}

/// 记录详情 →「修订记录」：这一条从记下到现在的每一版，只读。
struct ReviewRevisionsView: View {
  @Bindable var feature: ReviewFeature
  let record: ReviewRecord
  @Environment(\.reviewTheme) private var t
  @State private var items: [ReviewRevision] = []
  @State private var loaded = false
  @State private var error: String?
  var body: some View {
    List {
      ForEach(Array(items.enumerated()), id: \.offset) { _, revision in
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text(title(revision)).fontWeight(.semibold).foregroundStyle(t.ink)
            Spacer()
            Text(feature.fullTime(revision.at)).font(.caption).monospacedDigit().foregroundStyle(t.ink3)
          }
          ForEach(Array(lines(revision).enumerated()), id: \.offset) { _, line in
            Text(line).font(.subheadline).foregroundStyle(t.ink2).textSelection(.enabled)
          }
        }
        .padding(.vertical, 4)
        .listRowBackground(t.raised)
        .accessibilityIdentifier("review.revision.\(revision.kind)")
      }
      if let error { Text(error).foregroundStyle(t.ink3).listRowBackground(t.app) }
      else if !loaded { ProgressView().frame(maxWidth: .infinity).listRowBackground(t.app) }
      else if items.isEmpty { Text("还没有上传过，暂无修订").foregroundStyle(t.ink3).listRowBackground(t.app) }
    }
    .scrollContentBackground(.hidden)
    .background(t.app)
    .readableColumn()
    .navigationTitle("修订记录").navigationBarTitleDisplayMode(.inline)
    .task {
      do { items = try await feature.revisions(record.id).filter { $0.kind != "source_verified" }; loaded = true }
      catch { self.error = error.localizedDescription }
    }
  }
  private func title(_ revision: ReviewRevision) -> String {
    switch revision.kind {
    case "created": return "规则"
    case "assessment": return "判定"
    case "reflection": return revision.body["body"]?["publish"]?.bool == true ? "复盘 · 完成" : "复盘 · 草稿"
    case "void": return "作废"
    case "group": return "归并"
    default: return revision.kind
    }
  }
  private func lines(_ revision: ReviewRevision) -> [String] {
    let body = revision.body
    switch revision.kind {
    case "created":
      guard let draft = body["draft"], let rule = draft["rule"] else { return [] }
      var out: [String] = []
      let direction = rule["direction"]?.string.flatMap(ReviewDirection.init(rawValue:)) ?? .observe
      out.append(direction.title)
      if direction != .observe {
        if let target = rule["target"]?.number { out.append("目标 " + price(target)) }
        if let invalidation = rule["invalidation"]?.number { out.append("失效 " + price(invalidation)) }
        if let confirmation = rule["confirmation"]?.string.flatMap(ReviewConfirmation.init(rawValue:)) { out.append("判定 " + confirmation.title) }
        if let expires = rule["expires"]?.number { out.append("到期 " + feature.fullTime(Int64(expires))) }
      }
      if let text = draft["text"]?.string, !text.isEmpty { out.append("原话 " + text) }
      if let version = body["ruleVersion"]?.string { out.append("判定规则 " + version) }
      return out
    case "assessment":
      let outcome = body["outcome"]?.string.flatMap(ReviewOutcome.init(rawValue:)) ?? .needsVerification
      return [outcome.title] + (body["reason"]?.string.map { [$0] } ?? [])
    case "reflection":
      let reflection = body["body"]?["reflection"]
      let note = reflection?["note"]?.string ?? ""
      let next = reflection?["nextTime"]?.string ?? ""
      return ["现在怎么看：" + (note.isEmpty ? "未写" : note), "下次怎么做：" + (next.isEmpty ? "未写" : next)]
    case "group":
      return [body["body"]?["sameEpisode"]?.bool == true ? "与上一笔是同一次判断" : "独立判断"]
    default: return []
    }
  }
  private func price(_ value: Double) -> String { feature.price(value, symbol: record.draft.range.key) }
}

/// 记录详情里的「补图」：相册挑一张 → 压成 JPEG（≤ 5 MB）→ 传上去，横滑看。一条最多三张。
struct ReviewAttachmentsSection: View {
  @Bindable var feature: ReviewFeature
  let record: ReviewRecord
  @Environment(\.reviewTheme) private var t
  @State private var items: [ReviewAttachment] = []
  @State private var images: [UUID: UIImage] = [:]
  @State private var picked: PhotosPickerItem?
  @State private var busy = false
  @State private var error: String?
  @State private var page: UUID?
  var body: some View {
    Section("补图") {
      if !items.isEmpty {
        TabView(selection: $page) {
          ForEach(items) { item in
            ZStack(alignment: .topTrailing) {
              if let image = images[item.id] {
                Image(uiImage: image).resizable().scaledToFit()
                  .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
              } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
              Button { Task { await remove(item) } } label: {
                Image(systemName: "trash").font(.footnote.weight(.semibold)).foregroundStyle(t.danger)
                  .frame(width: 32, height: 32).background(t.raised.opacity(0.9), in: Circle())
              }
              .buttonStyle(.plain).padding(6)
              .accessibilityLabel("删除这张图")
            }
            .tag(Optional(item.id))
            .task { await fetch(item) }
          }
        }
        .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
        .frame(height: 240)
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .accessibilityIdentifier("review.attachments.pager")
      }
      // PhotosPicker 的 label 闭包不在主线程隔离里，先把要显示的值取出来再交进去。
      let loading = busy, count = items.count, limit = ReviewFeature.attachmentLimit, ink3 = t.ink3
      PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
        HStack {
          Label("补一张图", systemImage: "photo.badge.plus")
          Spacer()
          if loading { ProgressView() } else { Text("\(count)/\(limit)").monospacedDigit().foregroundStyle(ink3) }
        }
      }
      .disabled(busy || items.count >= ReviewFeature.attachmentLimit || record.serverId == nil)
      .accessibilityIdentifier("review.attachments.add")
      if let error { Text(error).font(.caption).foregroundStyle(t.ink3) }
    }
    .listRowBackground(t.raised)
    .task(id: record.id) { await reload() }
    .onChange(of: picked) { _, item in
      guard let item else { return }
      picked = nil
      Task { await upload(item) }
    }
  }
  private func reload() async {
    do { items = try await feature.attachments(record.id); error = nil } catch { self.error = error.localizedDescription }
  }
  private func fetch(_ item: ReviewAttachment) async {
    guard images[item.id] == nil, let data = await feature.attachmentImage(item.id), let image = UIImage(data: data) else { return }
    images[item.id] = image
  }
  private func upload(_ item: PhotosPickerItem) async {
    busy = true; error = nil
    defer { busy = false }
    guard let raw = try? await item.loadTransferable(type: Data.self), let data = Self.jpeg(raw) else {
      error = "这张图读不出来"; return
    }
    do {
      try await feature.addAttachment(data, to: record.id)
      await reload()
      page = items.last?.id
    } catch { self.error = error.localizedDescription }
  }
  private func remove(_ item: ReviewAttachment) async {
    do { try await feature.deleteAttachment(item.id); images.removeValue(forKey: item.id); await reload() }
    catch { self.error = error.localizedDescription }
  }
  /// 压成 JPEG：长边先收到 2048，还超 5 MB 就一轮轮缩边、降质量。
  static func jpeg(_ raw: Data) -> Data? {
    guard let image = UIImage(data: raw) else { return nil }
    var side: CGFloat = 2048; var quality: CGFloat = 0.82
    for _ in 0..<6 {
      let size = image.size
      let scale = min(1, side / max(size.width, size.height, 1))
      let target = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))
      let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
      let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
      if let out = scaled.jpegData(compressionQuality: quality), out.count <= ReviewFeature.attachmentMaxBytes { return out }
      side *= 0.75; quality = max(0.5, quality - 0.1)
    }
    return nil
  }
}
