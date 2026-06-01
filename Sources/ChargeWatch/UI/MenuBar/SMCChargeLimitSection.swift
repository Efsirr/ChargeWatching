import SwiftUI

/// 面板内"充电上限"分组——直接 SMC 控制（经 root helper），点一下即开。
/// 采用 StayAwake 同款原生 `GroupBox` + 原生 `Toggle .switch` / `Slider` / `Button`，
/// 文字一律 `.primary` / `.secondary`，滑块用系统强调色（`.tint`）。
/// 核心控件为原生 Slider（步进 5%，区间 80...100，对齐 SMCChargeLimiter.steps），
/// 仅在松手（onEditingChanged == false）写入 limiter，拖动途中不写盘，避免反复改写 SMC 配置。
struct SMCChargeLimitSection: View {
    @EnvironmentObject private var limiter: SMCChargeLimiter
    @EnvironmentObject private var stream: SampleStream
    /// 用于检测"系统上限 < CW 上限"冲突（两者同时启用时系统侧较低值会赢）。
    @EnvironmentObject private var chargeLimit: ChargeLimitController

    private var soc: Int? { stream.latest?.stateOfChargePercent }

    /// 拖动期间的就地草稿值；仅松手时写入 limiter，外部变化经 onChange 回灌。
    @State private var draft: Double = 80
    /// 冲突说明 popover 显隐。
    @State private var showConflictInfo: Bool = false

    /// 当 ChargeWatch 启用上限、系统也设了上限且系统更低时，返回系统的 SoC（实际生效值）。
    /// 其余场景（值相等 / CW 主导 / 系统无限制 / 状态未知 / CW 关闭）一律 nil。
    private var systemOverrideSoC: Int? {
        guard limiter.installed, limiter.enabled,
              case .limited(let sysSoc) = chargeLimit.state,
              sysSoc < limiter.limit
        else { return nil }
        return sysSoc
    }

    /// 与 SMCChargeLimiter.steps（80/85/90/95/100）对齐：5% 步进、80...100 区间。
    private static let sliderRange: ClosedRange<Double> = 80...100
    private static let sliderStep: Double = 5
    private static let tickValues: [Int] = SMCChargeLimiter.steps

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { draft = clampToRange(Double(limiter.limit)) }
        .onChange(of: limiter.limit) { newValue in
            let synced = clampToRange(Double(newValue))
            if draft != synced { draft = synced }
        }
    }

    private var header: some View {
        HStack(spacing: AppSpacing.s) {
            Label("充电上限", systemImage: AppIcon.chargeLimit)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.primary)
            Spacer()
            trailing.frame(minWidth: 56, alignment: .trailing)
        }
    }

    @ViewBuilder private var trailing: some View {
        if limiter.busy {
            ProgressView().controlSize(.small)
        } else if let sysSoc = systemOverrideSoC {
            conflictBadge(sysSoc: sysSoc)
        } else if limiter.enabled {
            percentBadge(limiter.limit, tint: AppColor.chargingActive)
        } else if let soc {
            percentBadge(soc, tint: .primary)
        } else {
            Text("—")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// 冲突徽标：用警告色显示系统实际生效的较低 SoC + "被系统设置覆盖"说明 + ⓘ 按钮（弹 popover）。
    /// 文案完整保留主谓宾，宽度不够时由 minimumScaleFactor 等比缩放，绝不分行避免破坏标题高度。
    private func conflictBadge(sysSoc: Int) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(sysSoc)")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(AppColor.warningHigh)
                Text("% 被系统设置覆盖")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppColor.warningHigh)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("当前实际生效 \(sysSoc) 百分比，被系统设置覆盖")

            Button {
                showConflictInfo.toggle()
            } label: {
                Image(systemName: AppIcon.info)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看冲突说明")
            .popover(isPresented: $showConflictInfo, arrowEdge: .top) {
                conflictPopoverContent(sysSoc: sysSoc)
            }
        }
    }

    /// 冲突说明 popover：标题 + 机制段 + 建议段 + 一键打开系统电池设置。
    /// 复用 ChargeLimitController.openSystemBatterySettings()（已带 fallback 链）。
    @ViewBuilder
    private func conflictPopoverContent(sysSoc: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: AppIcon.warning)
                    .foregroundStyle(AppColor.warningHigh)
                Text("充电上限被系统覆盖")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            (
                Text("系统设置上限 ")
                + Text("\(sysSoc)%").font(.system(size: 12, weight: .semibold)).foregroundColor(AppColor.warningHigh)
                + Text(" 比 ChargeWatch ")
                + Text("\(limiter.limit)%").font(.system(size: 12, weight: .semibold))
                + Text(" 低。两个机制同时生效时较低的会赢，所以充电会停在 ")
                + Text("\(sysSoc)%").font(.system(size: 12, weight: .semibold)).foregroundColor(AppColor.warningHigh)
                + Text("。")
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("建议把系统上限设到 100%（不限制），让 ChargeWatch 接管——5 档细粒度（80/85/90/95/100）、滞回缓冲、自动校准都在这里。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                chargeLimit.openSystemBatterySettings()
                showConflictInfo = false
            } label: {
                Text("打开系统设置 > 电池")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(AppSpacing.l)
        .frame(width: 300)
    }

    /// 头部百分比徽标：数字 monospacedDigit + 紧凑 % 后缀，层级清晰、宽度稳定。
    /// % 后缀骑在数字基线上、保持 .secondary 安静后缀，玻璃材质上不冲淡、不喧宾夺主。
    private func percentBadge(_ value: Int, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(value)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text("%")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var content: some View {
        if !limiter.installed {
            enablePrompt
        } else {
            Divider()
            // 说明在行首、开关贴行尾（系统设置开关行的标准布局），不居中。
            HStack(alignment: .center, spacing: AppSpacing.s) {
                rowLabel("启用充电上限", "将电量保持在设定上限附近")
                Spacer(minLength: AppSpacing.s)
                Toggle("启用充电上限", isOn: Binding(
                    get: { limiter.enabled },
                    set: { $0 ? limiter.enable(limit: limiter.limit) : limiter.disable() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(limiter.busy)
            }
            .frame(maxWidth: .infinity)

            if limiter.enabled {
                sliderControl
            } else {
                disabledHint
            }
        }
        if let err = limiter.lastError {
            Text(err)
                .font(.caption)
                .foregroundStyle(AppColor.discharging)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var enablePrompt: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text("开启后将电量保持在上限附近。首次需授权安装后台组件（仅一次）。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            // 说明文字保持前置占满整行；主操作按系统设置的 "primary right" 推到行尾。
            HStack {
                Spacer()
                Button("开启充电上限") { limiter.enable(limit: 80) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(limiter.busy)
            }
        }
    }

    private var sliderControl: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            readout
            Slider(
                value: $draft,
                in: Self.sliderRange,
                step: Self.sliderStep,
                onEditingChanged: { editing in
                    if !editing { commit() }
                }
            )
            .disabled(limiter.busy)
            .accessibilityValue("\(Int(draft.rounded())) 百分比")
            tickRuler
        }
    }

    private var readout: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("目标上限")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(draft.rounded()))")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AppColor.chargingActive)
                        .contentTransition(.numericText())
                    Text("%")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let soc {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("当前电量")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(soc)")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text("%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var tickRuler: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.tickValues.enumerated()), id: \.element) { index, tick in
                Text("\(tick)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(
                        Int(draft.rounded()) == tick ? .primary : .secondary
                    )
                    .frame(maxWidth: .infinity,
                           alignment: tickAlignment(index: index, count: Self.tickValues.count))
            }
        }
        .accessibilityHidden(true)
    }

    private var disabledHint: some View {
        Text("已安装后台组件，打开开关即可设定上限。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 松手提交：仅当落定值与当前 limiter.limit 不同才写盘，避免重复 setLimit。
    private func commit() {
        let value = Int(draft.rounded())
        guard value != limiter.limit else { return }
        limiter.setLimit(value)
    }

    private func clampToRange(_ value: Double) -> Double {
        min(max(value, Self.sliderRange.lowerBound), Self.sliderRange.upperBound)
    }

    private func tickAlignment(index: Int, count: Int) -> Alignment {
        if index == 0 { return .leading }
        if index == count - 1 { return .trailing }
        return .center
    }

    private func rowLabel(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
