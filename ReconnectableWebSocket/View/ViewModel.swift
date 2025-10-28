//
//  ViewModel.swift
//  ReconnectableWebSocket
//
//  Created by 강대훈 on 10/27/25.
//

import SwiftUI

@MainActor
final class ViewModel: ObservableObject {
    @Published var coinData: String = ""
    
    private var client: WebSocketClient
    
    init() {
        self.client = WebSocketClient(url: URL(string: "wss://api.upbit.com/websocket/v1")!)
    }
    
    func setUp() async {
        await connect()
        Task { await observeState() }
        Task { await observeIncome() }
        send()
    }
    
    func connect() async {
        await client.connect()
    }
    
    func disconnect() async {
        await client.disconnect()
    }
    
    func send() {
        Task { try await client.send(text: "[{ticket:test},{type:ticker,codes:[KRW-BTC]}]") }
    }
}

extension ViewModel {
    private func observeState() async {
        // 보통 WebSocket의 메세지는 상위 모듈에서 보내기 때문에 .connected가 되는 시점을 관찰할 필요가 있습니다.
        client.stateBroadCaster.sink { [weak self] state in
            guard let self = self else { return }
            if case .connected = state { send() }
        }.store(in: &client.cancellables)
    }
    
    private func observeIncome() async {
        guard let stream = client.incomingStream else { return }
        
        for await message in stream {
            switch message {
            case .data(let data):
                guard let coinData = try? JSONDecoder().decode(CoinDTO.self, from: data) else {
                    print("JSON 디코드 실패")
                    return
                }
                
                await MainActor.run {
                    print("\(coinData.changePrice)")
                    self.coinData = "\(coinData.changePrice)"
                }
            case .string(let string):
                print(string)
            @unknown default:
                fatalError()
            }
        }
    }
}
