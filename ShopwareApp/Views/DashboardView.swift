//
//  DashboardView.swift
//  ShopwareApp
//
//  Main dashboard: shop header, sales-channel selector, KPI cards, charts,
//  today's orders, top products, and low-stock alerts.
//

import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: ShopwareDashboardViewModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header — identity block with the shop switcher
                    ShopHeaderView(viewModel: viewModel, showSettings: $showSettings)
                        .riseIn(0)

                    // Sales channel selector
                    Menu {
                        Button {
                            Task { await viewModel.selectChannel(nil) }
                        } label: {
                            if viewModel.selectedChannelID == nil {
                                Label("All sales channels", systemImage: "checkmark")
                            } else {
                                Text("All sales channels")
                            }
                        }
                        ForEach(viewModel.salesChannels) { channel in
                            Button {
                                Task { await viewModel.selectChannel(channel.id) }
                            } label: {
                                if viewModel.selectedChannelID == channel.id {
                                    Label(channel.name, systemImage: "checkmark")
                                } else {
                                    Text(channel.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "cart")
                                .font(.subheadline)
                            Text(viewModel.selectedChannelName)
                                .font(.subheadline.weight(.bold))
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(Color.primaryText)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.border, lineWidth: 1))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .riseIn(0.06)

                    if let msg = viewModel.errorMessage { ErrorBanner(message: msg) }

                    // KPI cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(title: "Orders today", value: viewModel.metrics?.orderCountToday.formatted() ?? "-", accent: .shopwareBlue)
                        MetricCard(title: "Revenue today", value: viewModel.metrics?.todayRevenue.formatted(.currency(code: viewModel.metrics?.currencyCode ?? "EUR")) ?? "-", accent: .amber)
                        MetricCard(title: "Products", value: viewModel.metrics?.productCount.formatted() ?? "-", accent: .blue)
                        MetricCard(title: "Customers", value: viewModel.metrics?.customerCount.formatted() ?? "-", accent: .red)
                    }
                    .riseIn(0.12)

                    // Orders chart
                    ChartCard(
                        title: "Orders",
                        ranges: DateRange.allCases,
                        selectedRange: $viewModel.ordersRange,
                        isLoading: viewModel.isLoading,
                        onRangeChange: { Task { await viewModel.fetchOrdersHistory() } }
                    ) {
                        OrdersBarChart(buckets: viewModel.orderBuckets, range: viewModel.ordersRange)
                    }
                    .riseIn(0.18)

                    // Turnover chart
                    ChartCard(
                        title: "Turnover",
                        ranges: DateRange.allCases,
                        selectedRange: $viewModel.revenueRange,
                        isLoading: viewModel.isLoading,
                        onRangeChange: { Task { await viewModel.fetchRevenueHistory() } }
                    ) {
                        RevenueBarChart(buckets: viewModel.revenueBuckets, range: viewModel.revenueRange, currency: viewModel.metrics?.currencyCode ?? "EUR")
                    }
                    .riseIn(0.24)

                    // Sales by language
                    if !viewModel.languageStats.isEmpty {
                        LanguageBreakdownCard(
                            stats: viewModel.languageStats,
                            currency: viewModel.metrics?.currencyCode ?? "EUR"
                        )
                        .riseIn(0.27)
                    }

                    // Today's orders list
                    HStack {
                        Text("Today's orders")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primaryText)
                        Spacer()
                        Button {
                            Task { await viewModel.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline)
                                .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                                .animation(
                                    viewModel.isLoading
                                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                                        : .default,
                                    value: viewModel.isLoading
                                )
                        }
                        .buttonStyle(IconButtonStyle())
                        .disabled(viewModel.isLoading)
                    }

                    OrderList(orders: viewModel.metrics?.latestOrders ?? [], isLoading: viewModel.isLoading)
                        .riseIn(0.3)

                    // Top products
                    if !viewModel.topProducts.isEmpty {
                        Text("Top products · 30 days")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primaryText)
                        VStack(spacing: 0) {
                            ForEach(Array(viewModel.topProducts.enumerated()), id: \.element.id) { index, product in
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color.shopwareBlue)
                                        .frame(width: 24)
                                    Text(product.label)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.primaryText)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(product.quantitySold) sold")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.secondaryText)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                if product.id != viewModel.topProducts.last?.id {
                                    Divider().padding(.leading, 14)
                                }
                            }
                        }
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.border, lineWidth: 1))
                    }

                    // Low stock alert
                    if !viewModel.lowStockProducts.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.amber)
                            Text("Low stock")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.primaryText)
                        }
                        VStack(spacing: 0) {
                            ForEach(viewModel.lowStockProducts) { product in
                                HStack(spacing: 12) {
                                    Text(product.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.primaryText)
                                        .lineLimit(1)
                                    Spacer()
                                    Group {
                                        if product.stock == 0 {
                                            Text("Out of stock")
                                        } else {
                                            Text("\(product.stock) left")
                                        }
                                    }
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(product.stock == 0 ? Color.red.opacity(0.12) : Color.amber.opacity(0.12))
                                    .foregroundStyle(product.stock == 0 ? Color.red : Color.amber)
                                    .clipShape(Capsule())
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                if product.id != viewModel.lowStockProducts.last?.id {
                                    Divider().padding(.leading, 14)
                                }
                            }
                        }
                        .background(Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.border, lineWidth: 1))
                    }
                }
                .padding(20)
                .padding(.bottom, 32)
            }
            .background(Color.appBackground)
            .refreshable { await viewModel.refresh() }
            .task { await viewModel.refresh() }
            .navigationDestination(for: LatestOrder.self) { order in
                OrderDetailView(viewModel: viewModel, order: order)
            }
            .sheet(isPresented: $showSettings) {
                ShopSettingsView(viewModel: viewModel)
                    .appAppearance()
            }
        }
    }
}
