import SwiftUI

struct LoginView: View {
    @ObservedObject var authService: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
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
                                SecureField("••••••••", text: $password)
                                    .padding()
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(10)
                                    .focused($focusedField, equals: .password)
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
                        
                        Button(action: {
                            performLogin()
                        }) {
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
                        .padding(.horizontal, 30)
                        .padding(.top, 10)
                        
                        Text("Hilfe benötigt? Support kontaktieren")
                            .font(.footnote)
                            .foregroundColor(.blue)
                            .padding(.top, 20)
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
                    performLogin()
                }
            }
        }
    }
    
    private func performLogin() {
        // Validation
        if !email.contains("@") || email.count < 5 {
            errorMessage = "Bitte geben Sie eine gültige Email-Adresse ein."
            return
        }
        
        isLoading = true
        errorMessage = nil
        focusedField = nil
        
        Task {
            do {
                try await authService.login(email: email, password: password)
                isLoading = false
            } catch {
                errorMessage = "Login fehlgeschlagen: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}
