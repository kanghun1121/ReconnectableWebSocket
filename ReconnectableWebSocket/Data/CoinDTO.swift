//
//  CoinDTO.swift
//  ReconnectableWebSocket
//
//  Created by 강대훈 on 10/27/25.
//

import Foundation

struct CoinDTO: Decodable {
    let code: String /// 종목 코드
    let tradePrice: Double /// 현재 체결 가격
    let change: String /// 전일 대비 변화 (RISE, FALL, EVEN)
    let changePrice: Double /// 전일 대비 가격 변화
    let changeRate: Double /// 전일 대비 등락률

    enum CodingKeys: String, CodingKey {
        case code
        case tradePrice = "trade_price"
        case change
        case changePrice = "change_price"
        case changeRate = "change_rate"
    }
}
