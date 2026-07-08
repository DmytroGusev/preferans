import SwiftUI
import PreferansEngine

struct LastTrickView: View {
    var projection: PlayerGameProjection
    var trick: Trick

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("\(projection.displayName(for: trick.winner)) won")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(TableTheme.goldBright)
                    .multilineTextAlignment(.center)
                Text("Last trick")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(TableTheme.inkCreamSoft)
            }
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(trick.plays.enumerated()), id: \.offset) { _, play in
                    trickPlayColumn(play)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .feltSurface(.card, radius: TableTheme.Radius.md)
    }

    private func trickPlayColumn(_ play: CardPlay) -> some View {
        let isWinner = play.player == trick.winner
        return VStack(spacing: 8) {
            CardView(
                card: .known(play.card),
                size: .standard,
                region: .trick(seat: play.player)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isWinner ? TableTheme.goldBright.opacity(0.95) : .clear,
                                  lineWidth: isWinner ? 2 : 0)
            )
            .shadow(color: isWinner ? TableTheme.goldBright.opacity(0.45) : .clear,
                    radius: isWinner ? 12 : 0)
            Text(projection.displayName(for: play.player))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isWinner ? TableTheme.goldBright : TableTheme.inkCreamSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
    }
}
