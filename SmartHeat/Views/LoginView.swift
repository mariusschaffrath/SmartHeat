import SwiftUI

struct LoginView: View {
    @ObservedObject var authService: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    // Tap counter for hidden Simulator skip button
    @State private var setupTapCount = 0
    @State private var showSimulatorSkip = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 25) {
                ScrollView {
                    VStack(spacing: 30) {
                        Image(systemName: "flame.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .foregroundColor(.orange)
                            .padding(.top, 40)
                        
                        VStack(spacing: 8) {
                            Text("SmartHeat Cloud")
                                .font(.largeTitle)
                                .bold()
                            Text("Verbinden Sie sich mit Ihrem Dielle Ofen")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.secondary)
                                TextField("beispiel@mail.de", text: $email)
                                    .padding()
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(10)
                                    .textInputAutocapitalization(.never)
                                    .disableAutocorrection(true)
                                    .keyboardType(.emailAddress)
                                    .focused($focusedField, equals: .email)
                                    .submitLabel(.next)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Passwort")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.secondary)
                                HStack {
                                    if showPassword {
                                        TextField("Passwort", text: $password)
                                            .textInputAutocapitalization(.never)
                                            .disableAutocorrection(true)
                                            .focused($focusedField, equals: .password)
                                    } else {
                                        SecureField("••••••••", text: $password)
                                            .focused($focusedField, equals: .password)
                                    }
                                    
                                    Button(action: { showPassword.toggle() }) {
                                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(10)
                                .submitLabel(.done)
                            }
                        }
                        .padding(.horizontal, 30)
                        
                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(error)
                            }
                            .font(.callout)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal, 30)
                        }
                        
                        VStack(spacing: 12) {
                            Button(action: handleLoginTap) {
                                HStack {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .padding(.trailing, 10)
                                    }
                                    Text(isLoading ? "Anmeldung..." : "Anmelden")
                                        .bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(email.isEmpty || password.isEmpty || isLoading ? Color.gray : Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .disabled(email.isEmpty || password.isEmpty || isLoading)
                            
                            if showSimulatorSkip {
                                Button(action: skipToSimulator) {
                                    HStack {
                                        Image(systemName: "bolt.horizontal.fill")
                                        Text("🧪 Im Simulator-Modus fortfahren (Skip)")
                                            .bold()
                                    }
                                    .font(.footnote)
                                    .foregroundColor(.purple)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.purple.opacity(0.12))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 30)
                        .padding(.top, 10)
                    }
                }
            }
            .navigationBarHidden(true)
            .onTapGesture {
                focusedField = nil
            }
            .onSubmit {
                if focusedField == .email {
                    focusedField = .password
                } else {
                    handleLoginTap()
                }
            }
        }
    }
    
    private func handleLoginTap() {
        setupTapCount += 1
        if setupTapCount >= 3 {
            withAnimation {
                showSimulatorSkip = true
            }
        }
        performLogin()
    }
    
    private func performLogin() {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !cleanEmail.contains("@") || cleanEmail.count < 5 {
            errorMessage = "Bitte geben Sie eine gültige Email-Adresse ein."
            return
        }
        
        isLoading = true
        errorMessage = nil
        focusedField = nil
        
        Task {
            do {
                try await authService.login(email: cleanEmail, password: cleanPassword)
                KeychainService.shared.save(cleanEmail, key: "cloud_email")
                KeychainService.shared.save(cleanPassword, key: "cloud_password")
                isLoading = false
            } catch {
                errorMessage = "Login fehlgeschlagen: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func skipToSimulator() {
        withAnimation {
            authService.isAuthenticated = true
            let dummyEmail = email.isEmpty ? "simulator@smartheat.local" : email
            KeychainService.shared.save(dummyEmail, key: "cloud_email")
            KeychainService.shared.save("simulator123", key: "cloud_password")
        }
    }
}
