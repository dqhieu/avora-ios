//
//  ContentView.swift
//  Avora
//
//  Created by Hieu Dinh on 6/26/26.
//

import SwiftUI

struct ContentView: View {
  var body: some View {
    LoginView()
  }
}

private struct LoginView: View {
  var body: some View {
    ZStack {
      Color.black
        .ignoresSafeArea()

      Image("LoginBackground")
        .resizable()
        .scaledToFill()
        .ignoresSafeArea()

//      LinearGradient(
//        colors: [
//          .clear,
//          .black.opacity(0.28),
//          .black.opacity(0.5)
//        ],
//        startPoint: .center,
//        endPoint: .bottom
//      )
//      .ignoresSafeArea()

      VStack {
        Spacer()
        loginButton
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 28)
    }
  }

  @ViewBuilder
  private var loginButton: some View {
    if #available(iOS 26.0, *) {
      Button(action: logIn) {
        loginButtonLabel
      }
      .buttonStyle(.glassProminent)
      .tint(Color.clear)
    } else {
      Button(action: logIn) {
        loginButtonLabel
      }
      .buttonStyle(.plain)
      .background(.ultraThinMaterial, in: Capsule())
      .overlay {
        Capsule()
          .stroke(.white.opacity(0.22), lineWidth: 1)
      }
    }
  }

  private var loginButtonLabel: some View {
    Text("Sign in with Apple")
      .foregroundStyle(.black)
      .font(.headline.weight(.semibold))
      .frame(maxWidth: .infinity, minHeight: 56)
      .contentShape(.capsule)
  }

  private func logIn() {
    // Hook authentication here when the login flow is ready.
  }
}

#Preview {
  ContentView()
}
