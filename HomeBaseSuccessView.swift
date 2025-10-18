import SwiftUI

import SwiftUI

struct HomeBaseSuccessView: View {
    @EnvironmentObject private var authManager: AuthManager
    let onContinue: () -> Void
    
    // Theme colors
    private let goldColor = Color(red: 0.95, green: 0.75, blue: 0.3)
    private let darkBackground = Color(red: 0.08, green: 0.08, blue: 0.08)
    private let cardBackground = Color(red: 0.2, green: 0.2, blue: 0.2)
    
    var body: some View {
        ZStack {
            darkBackground.edgesIgnoringSafeArea(.all)
            successView
        }
        .navigationTitle("Success")
        .navigationBarBackButtonHidden(true)
    }
    
    private var successView: some View {
        VStack(spacing: 30) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("HOME BASE REGISTERED")
                .font(.title)
                .foregroundColor(goldColor)
            
            VStack(spacing: 10) {
                Text("Your Home Base")
                    .foregroundColor(.white)
                
                Text(authManager.homeBaseName)
                    .font(.title2)
                    .foregroundColor(goldColor)
                    .fontWeight(.bold)
            }
            .padding()
            .background(cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(goldColor, lineWidth: 1)
            )
            
            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GoldButtonStyle())
        }
        .padding(.top, 60)
        .padding(.horizontal, 20)
    }
}

