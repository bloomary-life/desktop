import Foundation

struct AppConfiguration: Decodable {
    struct API: Decodable {
        let baseURL: URL

        private enum CodingKeys: String, CodingKey {
            case baseURL
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let baseURLString = try container.decode(String.self, forKey: .baseURL)
            guard let baseURL = URL(string: baseURLString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .baseURL,
                    in: container,
                    debugDescription: "Invalid baseURL"
                )
            }
            self.baseURL = baseURL
        }
    }

    struct LinkedIn: Decodable {
        let callbackURLScheme: String
    }

    struct Storage: Decodable {
        let draftsKey: String
        let linkedInTokenKey: String
    }

    struct Paddle: Decodable {
        let environment: String
        let clientToken: String
        let priceProMonthly: String

        static let disabled = Paddle(environment: "sandbox", clientToken: "", priceProMonthly: "")
    }

    struct Scheduling: Decodable {
        let maxAheadDays: Int

        static let `default` = Scheduling(maxAheadDays: 15)
    }

    struct Observability: Decodable {
        let sentryDSN: String
        let sentryEnvironment: String
        let sentryTracesSampleRate: Double
        let telemetryDeckAppID: String
        let telemetryDeckNamespace: String

        static let disabled = Observability(
            sentryDSN: "",
            sentryEnvironment: "production",
            sentryTracesSampleRate: 0.1,
            telemetryDeckAppID: "",
            telemetryDeckNamespace: ""
        )
    }

    let api: API
    let linkedIn: LinkedIn
    let storage: Storage
    let paddle: Paddle
    let scheduling: Scheduling
    let observability: Observability

    private enum CodingKeys: String, CodingKey {
        case api
        case linkedIn
        case storage
        case paddle
        case scheduling
        case observability
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        api = try container.decode(API.self, forKey: .api)
        linkedIn = try container.decode(LinkedIn.self, forKey: .linkedIn)
        storage = try container.decode(Storage.self, forKey: .storage)
        paddle = try container.decodeIfPresent(Paddle.self, forKey: .paddle) ?? .disabled
        scheduling = try container.decodeIfPresent(Scheduling.self, forKey: .scheduling) ?? .default
        observability = try container.decodeIfPresent(Observability.self, forKey: .observability) ?? .disabled
    }

    static func load(bundle: Bundle = .main) -> AppConfiguration {
        guard let url = bundle.url(forResource: "AppConfiguration", withExtension: "plist") else {
            fatalError("Missing AppConfiguration.plist")
        }
        do {
            let data = try Data(contentsOf: url)
            return try PropertyListDecoder().decode(AppConfiguration.self, from: data)
        } catch {
            fatalError("Invalid AppConfiguration.plist: \(error)")
        }
    }
}
