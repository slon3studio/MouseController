import SwiftUI

struct ContentView: View {

    @State private var ipAddress = "172.20.10.2"
    @State private var isConnected = false

    var body: some View {
        if isConnected {
            MousePadView(
                host: ipAddress,
                onDisconect: {
                    isConnected = false
                }
            )
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.08, green: 0.09, blue: 0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 28) {
                    Spacer()

                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 72, weight: .semibold))
                        .foregroundColor(.white)

                    VStack(spacing: 8) {
                        Text("Remote Mouse")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)

                        Text("Control your Mac from your iPhone")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }

                    VStack(spacing: 14) {
                        TextField("Mac IP address", text: $ipAddress)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.12))
                            )

                        Button {
                            isConnected = true
                        } label: {
                            Text("Connect")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)

                    Spacer()

                    Text("Make sure the Mac app is running")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.bottom, 20)
                }
            }
        }
    }
}
