//
//  ContentView.swift
//  ReconnectableWebSocket
//
//  Created by 강대훈 on 10/27/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = ViewModel()
    
    var body: some View {
        VStack {
            Text(viewModel.coinData)
                .font(.title)
                .fontWeight(.bold)
        }
        .task {
            await viewModel.setUp()
        }
    }
}

#Preview {
    ContentView()
}
