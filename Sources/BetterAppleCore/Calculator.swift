import Foundation

public enum CalculatorError: LocalizedError, Equatable {
    case empty, invalidSyntax, divisionByZero, nonFinite, tooComplex
    public var errorDescription: String? {
        switch self {
        case .empty: return "Enter an expression."
        case .invalidSyntax: return "Check the expression. Use numbers, parentheses and + − × ÷ ^ %."
        case .divisionByZero: return "Cannot divide by zero."
        case .nonFinite: return "The result is outside the supported numeric range."
        case .tooComplex: return "The expression is too complex."
        }
    }
}

/// A bounded arithmetic parser. It does not use NSExpression, JavaScript, scripts, or evaluation APIs.
public enum Calculator {
    public static func evaluate(_ expression: String) throws -> Double {
        guard !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CalculatorError.empty }
        guard expression.utf8.count <= 1024 else { throw CalculatorError.tooComplex }
        var parser = Parser(expression)
        let result = try parser.expression(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.characters.count else { throw CalculatorError.invalidSyntax }
        guard result.isFinite else { throw CalculatorError.nonFinite }
        return result == 0 ? 0 : result
    }

    public static func formatted(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.12g", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private struct Parser {
        let characters: [Character]
        var index = 0
        init(_ text: String) { characters = Array(text) }
        mutating func skipWhitespace() { while index < characters.count && characters[index].isWhitespace { index += 1 } }
        mutating func consume(_ character: Character) -> Bool {
            skipWhitespace()
            guard index < characters.count, characters[index] == character else { return false }
            index += 1
            return true
        }
        func checked(_ value: Double) throws -> Double {
            guard value.isFinite else { throw CalculatorError.nonFinite }
            return value
        }
        mutating func expression(depth: Int) throws -> Double {
            guard depth < 64 else { throw CalculatorError.tooComplex }
            var result = try term(depth: depth + 1)
            while true {
                if consume("+") { result = try checked(result + term(depth: depth + 1)) }
                else if consume("-") || consume("−") { result = try checked(result - term(depth: depth + 1)) }
                else { return result }
            }
        }
        mutating func term(depth: Int) throws -> Double {
            var result = try unary(depth: depth + 1)
            while true {
                if consume("*") || consume("×") { result = try checked(result * unary(depth: depth + 1)) }
                else if consume("/") || consume("÷") {
                    let divisor = try unary(depth: depth + 1)
                    guard divisor != 0 else { throw CalculatorError.divisionByZero }
                    result = try checked(result / divisor)
                } else { return result }
            }
        }
        mutating func unary(depth: Int) throws -> Double {
            guard depth < 64 else { throw CalculatorError.tooComplex }
            if consume("+") { return try unary(depth: depth + 1) }
            if consume("-") || consume("−") { return try -unary(depth: depth + 1) }
            return try power(depth: depth + 1)
        }
        mutating func power(depth: Int) throws -> Double {
            var result = try primary(depth: depth + 1)
            while consume("%") { result /= 100 }
            if consume("^") { result = try checked(pow(result, unary(depth: depth + 1))) }
            return result
        }
        mutating func primary(depth: Int) throws -> Double {
            guard depth < 64 else { throw CalculatorError.tooComplex }
            if consume("(") {
                let result = try expression(depth: depth + 1)
                guard consume(")") else { throw CalculatorError.invalidSyntax }
                return result
            }
            skipWhitespace()
            let start = index
            var hasDigit = false
            while index < characters.count && characters[index].isASCII && characters[index].isNumber { hasDigit = true; index += 1 }
            if index < characters.count && characters[index] == "." {
                index += 1
                while index < characters.count && characters[index].isASCII && characters[index].isNumber { hasDigit = true; index += 1 }
            }
            guard hasDigit else { throw CalculatorError.invalidSyntax }
            if index < characters.count && (characters[index] == "e" || characters[index] == "E") {
                index += 1
                if index < characters.count && (characters[index] == "+" || characters[index] == "-") { index += 1 }
                let exponentStart = index
                while index < characters.count && characters[index].isASCII && characters[index].isNumber { index += 1 }
                guard index > exponentStart else { throw CalculatorError.invalidSyntax }
            }
            guard let number = Double(String(characters[start..<index])) else { throw CalculatorError.invalidSyntax }
            return try checked(number)
        }
    }
}
