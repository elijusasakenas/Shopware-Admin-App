//
//  ContentView.swift
//  ShopwareApp
//
//  Root view: boots the dashboard view model and routes between the
//  connect screen and the dashboard, applying the chosen appearance/locale.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ShopwareDashboardViewModel()
    @AppStorage(AppLanguage.storageKey) private var appLanguageCode = AppLanguage.system.rawValue

    var body: some View {
        Group {
            if viewModel.isBooting {
                ProgressView()
                    .tint(.shopwareBlue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
            } else if viewModel.connection == nil {
                // No shop yet: the connect screen is the whole app.
                ConnectView(viewModel: viewModel)
            } else {
                DashboardView(viewModel: viewModel)
                    // Adding another shop while one is active: present over it.
                    .sheet(isPresented: $viewModel.isAddingShop) {
                        ConnectView(viewModel: viewModel)
                            .appAppearance()
                    }
            }
        }
        .appAppearance()
        .environment(\.locale, AppLanguage(rawValue: appLanguageCode)?.locale ?? .autoupdatingCurrent)
        .task { await viewModel.boot() }
    }
}
