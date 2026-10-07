import Foundation

enum Side {
    case player, opponent
    var other: Side { self == .player ? .opponent : .player }
}

/// 网球计分：0 / 15 / 30 / 40 / 平分 / 占先，赢局后清零。
final class MatchState {
    private(set) var playerPoints = 0
    private(set) var opponentPoints = 0
    private(set) var playerGames = 0
    private(set) var opponentGames = 0
    private(set) var longestRally = 0
    private(set) var pointsPlayed = 0

    var pointsText: String {
        func name(_ p: Int) -> String { ["0", "15", "30", "40"][min(p, 3)] }
        if playerPoints >= 3 && opponentPoints >= 3 {
            if playerPoints == opponentPoints { return "Deuce" }
            return playerPoints > opponentPoints ? "Ad In" : "Ad Out"
        }
        return "\(name(playerPoints)) : \(name(opponentPoints))"
    }

    var gamesText: String { "\(playerGames) : \(opponentGames)" }

    /// 返回 true 表示这一分结束了一局。
    @discardableResult
    func award(_ side: Side, rallyLength: Int) -> Bool {
        pointsPlayed += 1
        longestRally = max(longestRally, rallyLength)
        if side == .player { playerPoints += 1 } else { opponentPoints += 1 }
        if playerPoints >= 4 && playerPoints - opponentPoints >= 2 {
            playerGames += 1
            playerPoints = 0; opponentPoints = 0
            return true
        }
        if opponentPoints >= 4 && opponentPoints - playerPoints >= 2 {
            opponentGames += 1
            playerPoints = 0; opponentPoints = 0
            return true
        }
        return false
    }

    func reset() {
        playerPoints = 0; opponentPoints = 0
        playerGames = 0; opponentGames = 0
        longestRally = 0; pointsPlayed = 0
    }
}
