import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: Session

    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?
    enum Field { case username, password }

    var body: some View {
        VStack(spacing: 20) {
            Text("Tribune")
                .font(.largeTitle).bold()

            VStack(alignment: .leading, spacing: 12) {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .password }

                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit { submit() }
            }
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal)

            if let error = session.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }

            Button(action: submit) {
                if case .authenticating = session.state {
                    ProgressView().padding(.vertical, 2)
                } else {
                    Text("Sign In").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit || isBusy)
            .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .padding(.top, 60)
        .onAppear {
            // put cursor in username on first show
            focusedField = .username
        }
    }

    private var isBusy: Bool {
        if case .authenticating = session.state { return true }
        return false
    }

    private var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty
    }

    private func submit() {
        guard canSubmit, !isBusy else { return }
        session.signIn(username: username, password: password)
    }
}
