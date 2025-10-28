//
//  WebSocketState.swift
//  ReconnectableWebSocket
//
//  Created by 강대훈 on 10/27/25.
//

import Foundation

public enum WebSocket {
    public enum State: Sendable {
        case connecting, connected
        case closed
        case reconnecting
    }
}
