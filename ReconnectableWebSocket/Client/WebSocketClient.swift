//
//  WebSocketClient.swift
//  ReconnectableWebSocket
//
//  Created by 강대훈 on 10/27/25.
//

import Foundation
import Combine

public final class WebSocketClient: NSObject {
    /// WebSocket의 상태 변화를 여러 Consumer에게 동시에 전달하는 브로드캐스터
    public var cancellables: Set<AnyCancellable> = .init()
    public var stateBroadCaster: PassthroughSubject<WebSocket.State, Never>
    
    /// 메세지 채널
    public var incomingStream: AsyncStream<URLSessionWebSocketTask.Message>?
    private var incomingContinuations: AsyncStream<URLSessionWebSocketTask.Message>.Continuation?
    
    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    
    /// 메시지 수신 task
    private var receiveTask: Task<Void, Error>?
    /// 핑 전송 task
    private var healthCheck: Task<Void, Error>?
    
    private var pingInterval: Duration = .seconds(30)
    private var pingTimeout: Duration = .seconds(10)
    
    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
        self.stateBroadCaster = PassthroughSubject<WebSocket.State, Never>()
        
        super.init()
        
        incomingStream = AsyncStream<URLSessionWebSocketTask.Message> { cont in
            self.incomingContinuations = cont
        }
        
        observeState()
    }
    
    /// 웹소켓 세션을 연결하고 작업을 생성합니다.
    public func connect() async {
        stateBroadCaster.send(.connecting)
        self.task = session.webSocketTask(with: url)
        task?.delegate = self
        task?.resume()
    }
    
    /// 명시적으로 현재 WebSocket 연결을 정상적으로 종료합니다.
    ///
    /// 이 메서드는 서버와의 WebSocket 연결을 `normalClosure` 코드로 닫습니다.
    public func disconnect() async {
        task?.cancel(with: .normalClosure, reason: nil)
    }

    /// 텍스트 형태의 메시지를 WebSocket 서버로 전송합니다.
    public func send(text: String) async throws {
        try await task?.send(.string(text))
    }
    
    /// 바이너리(Data) 형태의 메시지를 WebSocket 서버로 전송합니다.
    public func send(data: Data) async throws {
        try await task?.send(.data(data))
    }
    
    deinit {
        debugPrint(String(describing: Self.self), #function)
        task?.cancel()
        task = nil
        cancellables.removeAll()
        incomingContinuations?.finish()
    }
}

// MARK: - Private
extension WebSocketClient {
    /// 서버로 Ping 프레임을 전송하여 연결 상태를 확인합니다.
    private func sendPing() async throws {
        // 클로저 형태의 sendPing 메소드를 async-await 문법으로 변경합니다.
        return try await withCheckedThrowingContinuation { continuation in
            task?.sendPing { error in
                Task {
                    if let error {
                        debugPrint("Ping Failed: \(error)")
                        continuation.resume(throwing: error)
                        return
                    }
                    
                    continuation.resume()
                }
            }
        }
    }
    
    /// WebSocket의 상태 변화를 관찰하고 각 상태에 맞는 동작을 수행합니다.
    private func observeState() {
        stateBroadCaster.sink { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .connecting:
                debugPrint("Connecting")
            case .connected:
                debugPrint("Connected")
                receive()
                checkingAlive()
            case .closed:
                debugPrint("Closed")
                release()
            case .reconnecting:
                debugPrint("Reconnecting")
                Task { await self.reconnect() }
            }
        }.store(in: &cancellables)
    }
    
    /// 서버로부터 WebSocket 메시지를 지속적으로 수신합니다.
    private func receive() {
        receiveTask?.cancel()
        
        receiveTask = Task {
            do {
                while true {
                    guard let task else { return }
                    let message = try await task.receive()
                    incomingContinuations?.yield(message)
                }
            } catch {
                print("메시지의 크기가 너무 크거나 웹소켓이 종료되었습니다.")
            }
        }
    }
    
    /// 주기적으로 Ping을 전송하여 WebSocket 연결 상태를 점검합니다.
    private func checkingAlive() {
        healthCheck?.cancel()
        
        healthCheck = Task {
            do {
                while true {
                    try await Task.sleep(until: .now + pingInterval)
                    try await performWithTimeout(sendPing, at: pingTimeout)
                }
            } catch is CancellationError {
                debugPrint("작업이 취소되었습니다.")
            } catch {
                stateBroadCaster.send(.reconnecting)
            }
        }
    }
    
    /// WebSocket 재연결을 시도합니다.
    private func reconnect() async {
        try? await Task.sleep(for: .seconds(2))
        await connect()
    }
    
    /// WebSocket 클라이언트의 모든 비동기 작업과 연결을 종료하고 리소스를 정리합니다.
    private func release() {
        receiveTask?.cancel()
        receiveTask = nil
        healthCheck?.cancel()
        healthCheck = nil
        task = nil
    }
}

// MARK: 웹 소켓 Delegate로 소켓 응답 및 종료 event를 받아 처리합니다.
extension WebSocketClient: URLSessionWebSocketDelegate {
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        stateBroadCaster.send(.connected)
    }
    
    // 웹소켓으로부터 Close Frame을 받았을 때. (정상 종료로 닫혔을 때)
    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        if closeCode == .normalClosure { stateBroadCaster.send(.closed) }
    }
    
    // 세션 레벨에서 작업이 완전히 종료됐을 때.
    // 1. 네트워크 닫힘, 2. 에러로 종료, 3. 정상적으로 완료
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let _ = error {
            stateBroadCaster.send(.reconnecting)
        }
    }
}

