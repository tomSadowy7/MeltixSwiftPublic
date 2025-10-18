// Colors.swift
import SwiftUI

extension Color {
    static let gold = Color(red: 212/255, green: 175/255, blue: 55/255)
    static let darkGold = Color(red: 180/255, green: 145/255, blue: 40/255)
    static let jetBlack = Color(red: 20/255, green: 20/255, blue: 20/255)
    static let charcoal = Color(red: 40/255, green: 40/255, blue: 40/255)
    static let charcoalGray = Color(red: 0.2, green: 0.2, blue: 0.2)
}

// Add Button Styles below Color extensions
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.gold)
            .foregroundColor(.black)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.darkGold, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
