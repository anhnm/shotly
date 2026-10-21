import SwiftUI

struct BuyMeACoffeeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var amountString: String = "50000"
    @State private var description: String = ""
    @State private var showQR: Bool = false
    @State private var generatedURL: URL? = nil
    
    private let quickDenominations = [
        (label: "20.000", value: 20000),
        (label: "30.000", value: 30000),
        (label: "50.000", value: 50000),
        (label: "100.000", value: 100000),
        (label: "200.000", value: 200000)
    ]
    
    var parsedAmount: Int {
        if amountString.isEmpty {
            return 50000
        }
        return Int(amountString) ?? 0
    }
    
    var isValidAmount: Bool {
        return parsedAmount >= 5000
    }
    
    // Theme Colors matching the web screenshots
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.05, green: 0.08, blue: 0.06) : Color(red: 0.95, green: 0.97, blue: 0.95)
    }
    
    private var accentGreen: Color {
        colorScheme == .dark ? Color(red: 0.29, green: 0.87, blue: 0.50) : Color(red: 0.09, green: 0.69, blue: 0.38)
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.12, blue: 0.10) : Color.white
    }
    
    private var textColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.05, green: 0.10, blue: 0.07)
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color(red: 0.6, green: 0.7, blue: 0.65) : Color(red: 0.3, green: 0.4, blue: 0.35)
    }
    
    private var inputBorderColor: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.22, blue: 0.18) : Color(red: 0.8, green: 0.85, blue: 0.82)
    }
    
    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header Close Button (Top Right)
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(textColor)
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                if !showQR {
                    formView
                } else {
                    thankYouView
                }
            }
        }
        .frame(width: 440, height: 560)
    }
    
    private var formView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header Content
            VStack(alignment: .leading, spacing: 4) {
                // Coffee Icon Box
                HStack {
                    Text("☕")
                        .font(.system(size: 28))
                        .frame(width: 50, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(accentGreen.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(accentGreen.opacity(0.3), lineWidth: 1)
                                )
                        )
                    Spacer()
                }
                .padding(.bottom, 8)
                
                Text("SUPPORT SHOTLY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(accentGreen)
                    .tracking(1.5)
                
                Text("Buy Me a Coffee")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(textColor)
                    .padding(.bottom, 2)
                
                Text("Your support helps me keep improving Shotly and building useful macOS tools.")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryTextColor)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            
            // Amount Input Field
            VStack(alignment: .leading, spacing: 6) {
                Text("Amount")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(secondaryTextColor)
                
                HStack(spacing: 8) {
                    TextField("50000", text: $amountString)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .textFieldStyle(.plain)
                        .foregroundColor(textColor)
                        .onChange(of: amountString) { oldValue, newValue in
                            let filtered = newValue.filter { "0123456789".contains($0) }
                            if filtered != newValue {
                                amountString = filtered
                            }
                        }
                    
                    Spacer()
                    
                    // Stepper control & Currency
                    HStack(spacing: 6) {
                        VStack(spacing: 2) {
                            Button {
                                adjustAmount(by: 5000)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(secondaryTextColor)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                adjustAmount(by: -5000)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(secondaryTextColor)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text("VND")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(secondaryTextColor)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(cardBackgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(accentGreen.opacity(0.8), lineWidth: 1.5)
                )
            }
            .padding(.horizontal, 24)
            
            // Quick selection denominations
            HStack(spacing: 8) {
                ForEach(quickDenominations, id: \.value) { item in
                    Button {
                        amountString = "\(item.value)"
                    } label: {
                        Text(item.label)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(parsedAmount == item.value ? accentGreen : cardBackgroundColor)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(parsedAmount == item.value ? Color.clear : accentGreen.opacity(0.2), lineWidth: 1)
                            )
                            .foregroundColor(parsedAmount == item.value ? (colorScheme == .dark ? .black : .white) : textColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            
            Text("Choose an amount above or enter any value from 5,000 VND.")
                .font(.system(size: 11))
                .foregroundColor(secondaryTextColor)
                .padding(.horizontal, 24)
                .padding(.top, -6)
            
            // Transfer Message Input Field
            VStack(alignment: .leading, spacing: 6) {
                Text("Transfer message")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(secondaryTextColor)
                
                TextField("Ung ho Shotly", text: $description)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(cardBackgroundColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(inputBorderColor, lineWidth: 1)
                            )
                    )
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Submit Button
            Button {
                generateQR()
            } label: {
                HStack {
                    Spacer()
                    Text("☕ Buy Me a Coffee")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isValidAmount ? (colorScheme == .dark ? .black : .white) : Color.white.opacity(0.6))
                    Spacer()
                }
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isValidAmount ? accentGreen : Color.gray)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isValidAmount)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
    
    private var thankYouView: some View {
        VStack(alignment: .center, spacing: 14) {
            // Heart Icon Box
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("❤️")
                        .font(.system(size: 24))
                        .frame(width: 50, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.red.opacity(0.12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                                )
                        )
                    Spacer()
                }
                .padding(.bottom, 4)
                
                Text("THANK YOU")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(accentGreen)
                    .tracking(1.5)
                
                Text("Thank you from the bottom of my heart.")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(textColor)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text("Your kindness means a lot to me and gives Shotly more room to grow. Thank you sincerely for supporting my work.")
                    .font(.system(size: 13))
                    .foregroundColor(secondaryTextColor)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            
            // QR Code Container
            VStack {
                if let url = generatedURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            VStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Creating QR...")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 170, height: 170)
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 170, height: 170)
                        case .failure:
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.red)
                                Text("Failed to load QR")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .frame(width: 170, height: 170)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .padding(10)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
            
            // Amount & Message Table
            VStack(spacing: 0) {
                HStack {
                    Text("Amount")
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    Text(formatVND(parsedAmount))
                        .fontWeight(.bold)
                        .foregroundColor(textColor)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                
                Divider()
                    .background(inputBorderColor.opacity(0.5))
                
                HStack {
                    Text("Message")
                        .foregroundColor(secondaryTextColor)
                    Spacer()
                    let cleanDes = removeVietnameseAccents(from: description.isEmpty ? "Ung ho Shotly" : description)
                    Text(cleanDes)
                        .fontWeight(.bold)
                        .foregroundColor(textColor)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
            }
            .font(.system(size: 12))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(inputBorderColor, lineWidth: 1)
            )
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Back Button Link
            Button {
                showQR = false
            } label: {
                Text("Change amount or message")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accentGreen)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
    }
    
    private func adjustAmount(by delta: Int) {
        let current = parsedAmount
        let newAmount = max(5000, current + delta)
        amountString = "\(newAmount)"
    }
    
    private func generateQR() {
        let amount = parsedAmount
        let cleanDescription = removeVietnameseAccents(from: description.isEmpty ? "Ung ho Shotly" : description)
        let encodedDes = cleanDescription.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let urlString = "https://qr.sepay.vn/img?acc=692696969&bank=MB&amount=\(amount)&des=\(encodedDes)"
        self.generatedURL = URL(string: urlString)
        self.showQR = true
    }
    
    private func formatVND(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + " VND"
    }
    
    private func removeVietnameseAccents(from string: String) -> String {
        var result = string
        
        let replacements: [String: String] = [
            "à": "a", "á": "a", "ả": "a", "ã": "a", "ạ": "a",
            "ă": "a", "ằ": "a", "ắ": "a", "ẳ": "a", "ẵ": "a", "ặ": "a",
            "â": "a", "ầ": "a", "ấ": "a", "ẩ": "a", "ẫ": "a", "ậ": "a",
            "đ": "d",
            "è": "e", "é": "e", "ẻ": "e", "ẽ": "e", "ẹ": "e",
            "ê": "e", "ề": "e", "ế": "e", "ể": "e", "ễ": "e", "ệ": "e",
            "ì": "i", "í": "i", "ỉ": "i", "ĩ": "i", "ị": "i",
            "ò": "o", "ó": "o", "ỏ": "o", "õ": "o", "ọ": "o",
            "ô": "o", "ồ": "o", "ố": "o", "ổ": "o", "ỗ": "o", "ộ": "o",
            "ơ": "o", "ờ": "o", "ớ": "o", "ở": "o", "ỡ": "o", "ợ": "o",
            "ù": "u", "ú": "u", "ủ": "u", "ũ": "u", "ụ": "u",
            "ư": "u", "ừ": "u", "ứ": "u", "ử": "u", "ữ": "u", "ự": "u",
            "ỳ": "y", "ý": "y", "ỷ": "y", "ỹ": "y", "ỵ": "y",
            
            "À": "A", "Á": "A", "Ả": "A", "Ã": "A", "Ạ": "A",
            "Ă": "A", "Ằ": "A", "Ắ": "A", "Ẳ": "A", "Ẵ": "A", "Ặ": "A",
            "Â": "A", "Ầ": "A", "Ấ": "A", "Ẩ": "A", "Ẫ": "A", "Ậ": "A",
            "Đ": "D",
            "È": "E", "É": "E", "Ẻ": "E", "Ẽ": "E", "Ẹ": "E",
            "Ê": "E", "Ề": "E", "Ế": "E", "Ể": "E", "Ễ": "E", "Ệ": "E",
            "Ì": "I", "Í": "I", "Ỉ": "I", "Ĩ": "I", "Ị": "I",
            "Ò": "O", "Ó": "O", "Ỏ": "O", "Õ": "O", "Ọ": "O",
            "Ô": "O", "Ồ": "O", "Ố": "O", "Ổ": "O", "Ộ": "O",
            "Ơ": "O", "Ờ": "O", "Ớ": "O", "Ở": "O", "Ỡ": "O", "Ợ": "O",
            "Ù": "U", "Ú": "U", "Ủ": "U", "Ũ": "U", "Ụ": "U",
            "Ư": "U", "Ừ": "U", "Ứ": "U", "Ử": "U", "Ữ": "U", "Ự": "U",
            "Ỳ": "Y", "Ý": "Y", "Ỷ": "Y", "Ỹ": "Y", "Ỵ": "Y"
        ]
        
        for (accented, plain) in replacements {
            result = result.replacingOccurrences(of: accented, with: plain)
        }
        
        return result.folding(options: .diacriticInsensitive, locale: .current)
    }
}
