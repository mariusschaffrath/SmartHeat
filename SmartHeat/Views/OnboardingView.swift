import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: StoveViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            
            // Decorative elements
            Circle()
                .fill(Color.orange.opacity(0.1))
                .frame(width: 400, height: 400)
                .offset(x: 150, y: -350)
            
            VStack(spacing: 30) {
                Spacer()
                
                VStack(spacing: 16) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                        )
                        .shadow(color: .orange.opacity(0.3), radius: 15, x: 0, y: 8)
                    
                    Text("SmartHeat")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    
                    Text("Ihr Zuhause, perfekt temperiert.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        TextField("E-Mail", text: $email)
                            .padding()
                            .background(Color(uiColor: .secondarySystemBackground))
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Divider().padding(.horizontal)
                        
                        HStack {
                            if showPassword {
                                TextField("Passwort", text: $password)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            } else {
                                SecureField("Passwort", text: $password)
                            }
                            
                            Button(action: { showPassword.toggle() }) {
                                Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                    .foregroundColor(.gray)
                                    .padding(.trailing, 8)
                            }
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                    }
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    )
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 30)
                
                VStack(spacing: 12) {
                    Button(action: startSetup) {
                        HStack {
                            if isAuthenticating {
                                ProgressView().tint(.white)
                                    .padding(.trailing, 8)
                            }
                            Text(isAuthenticating ? "Verbindung wird hergestellt..." : "Einrichtung starten")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(email.isEmpty || password.isEmpty ? Color.gray.opacity(0.3) : Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: .orange.opacity(email.isEmpty ? 0 : 0.3), radius: 10, x: 0, y: 5)
                    }
                    .disabled(email.isEmpty || password.isEmpty || isAuthenticating)
                }
                .padding(.horizontal, 30)
                
                Spacer()
                
                Text("Verschlüsselte Speicherung im iOS Keychain")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
            }
        }
    }
    
    private func startSetup() {
        withAnimation {
            isAuthenticating = true
            errorMessage = nil
        }
        
        Task {
            do {
                try await viewModel.authService.login(email: email, password: password)
                KeychainService.shared.save(email, key: "cloud_email")
                KeychainService.shared.save(password, key: "cloud_password")
                withAnimation { isAuthenticating = false }
            } catch {
                withAnimation {
                    errorMessage = "Login fehlgeschlagen. Bitte prüfen Sie Ihre Zugangsdaten."
                    isAuthenticating = false
                }
            }
        }
    }
}
