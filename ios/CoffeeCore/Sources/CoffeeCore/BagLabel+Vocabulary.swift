import Foundation

/// The names of a coffee's origin as labels print them, for picking them
/// out of a label's text. Each is how the app writes it, then any other
/// ways it's spelled, folded (lowercased, without accents).
extension BagLabel {
    typealias Name = (name: String, spellings: [String])

    static var countries: [Name] {
        [
            ("Ethiopia", []), ("Kenya", []), ("Colombia", []), ("Ecuador", []), ("Peru", []), ("Bolivia", []),
            ("Brazil", ["brasil"]), ("Burundi", []), ("Rwanda", []), ("Uganda", []), ("Tanzania", []),
            ("DR Congo", ["dr congo", "drc", "democratic republic of congo", "democratic republic of the congo", "congo"]),
            ("Yemen", []), ("Panama", []), ("Costa Rica", []), ("Guatemala", []), ("Honduras", []), ("Nicaragua", []),
            ("El Salvador", []), ("Mexico", []), ("Jamaica", []), ("Hawaii", []), ("Puerto Rico", []),
            ("Dominican Republic", []), ("Cuba", []), ("Haiti", []), ("Venezuela", []), ("Indonesia", []),
            ("Timor-Leste", ["timor leste", "east timor"]), ("Papua New Guinea", ["png"]), ("India", []), ("China", []),
            ("Vietnam", []), ("Thailand", []), ("Laos", []), ("Myanmar", []), ("Philippines", []), ("Taiwan", []),
            ("Nepal", []), ("Malawi", []), ("Zambia", []), ("Zimbabwe", []), ("Cameroon", []),
        ]
    }

    static var regions: [Name] {
        [
            // Colombia
            ("Huila", []), ("Cauca", []), ("Nariño", []), ("Tolima", []), ("Antioquia", []), ("Quindío", []),
            ("Santander", []), ("Risaralda", []), ("Caldas", []),
            // Ethiopia
            ("Sidama", ["sidamo"]), ("Yirgacheffe", ["yirgachefe"]), ("Guji", []), ("Jimma", []), ("Limu", []),
            ("Harrar", ["harar"]), ("Bensa", []), ("Gedeb", []), ("Kochere", []),
            // Kenya
            ("Nyeri", []), ("Kirinyaga", []), ("Embu", []), ("Murang'a", ["muranga"]), ("Kiambu", []), ("Meru", []),
            // Ecuador, Peru, Bolivia
            ("Pichincha", []), ("Loja", []), ("Zamora", []), ("Imbabura", []), ("Cajamarca", []), ("Cusco", []),
            ("Puno", []), ("Amazonas", []), ("Junín", []), ("San Martín", []), ("Caranavi", []),
            // Central America and Mexico
            ("Boquete", []), ("Chiriquí", []), ("Volcán", []), ("Antigua", []), ("Huehuetenango", []),
            ("Acatenango", []), ("Atitlán", []), ("Cobán", []), ("Tarrazú", []), ("West Valley", []),
            ("Central Valley", []), ("Naranjo", []), ("Santa Barbara", []), ("Marcala", []), ("Copán", []),
            ("Ocotepeque", []), ("La Paz", []), ("Intibucá", []), ("Comayagua", []), ("Jinotega", []),
            ("Nueva Segovia", []), ("Matagalpa", []), ("Chalatenango", []), ("Santa Ana", []), ("Apaneca", []),
            ("Oaxaca", []), ("Chiapas", []), ("Veracruz", []),
            // Brazil
            ("Minas Gerais", []), ("Cerrado", []), ("Mogiana", []), ("Sul de Minas", []), ("Mantiqueira", []),
            // Burundi, Rwanda, Uganda, Tanzania
            ("Kayanza", []), ("Ngozi", []), ("Muramvya", []), ("Nyamasheke", []), ("Rulindo", []), ("Huye", []),
            ("Nyamagabe", []), ("Gakenke", []), ("Mount Elgon", []), ("Bugisu", []), ("Mbeya", []),
            ("Kilimanjaro", []),
            // Asia and the Pacific
            ("Aceh", []), ("Gayo", []), ("Kerinci", []), ("Toraja", []), ("Sumatra", []), ("Sulawesi", []),
            ("Yunnan", []), ("Kona", []),
        ]
    }

    static var varieties: [Name] {
        [
            ("Gesha", ["geisha"]), ("Pink Bourbon", []), ("Red Bourbon", []), ("Yellow Bourbon", []),
            ("Bourbon", []), ("Typica", []), ("Caturra", []), ("Catuai", ["catuaí"]), ("Pacas", []),
            ("Pacamara", []), ("Maragogype", []), ("Mundo Novo", []), ("Villa Sarchi", []), ("Castillo", []),
            ("Catimor", []), ("Sarchimor", []), ("Tabi", []), ("Sidra", []), ("Mejorado", []), ("Wush Wush", []),
            ("Chiroso", []), ("Laurina", []), ("Eugenioides", []), ("Parainema", []), ("Lempira", []),
            ("Marsellesa", []), ("Obata", []), ("Java", []), ("Maracaturra", []), ("Bernardina", []), ("SL28", ["sl 28"]),
            ("SL34", ["sl 34"]), ("Ruiru 11", []), ("Batian", []), ("K7", []), ("Landrace", []),
            ("Heirloom", []), ("74110", []), ("74112", []), ("74158", []), ("JARC", []), ("Kurume", []),
            ("Dega", []), ("Wolisho", []),
        ]
    }

    /// Words that make a process on their own: "Washed", "Natural".
    static var processWords: Set<String> {
        ["washed", "natural", "honey", "anaerobic", "carbonic", "hulled", "pulped", "fermented", "fermentation", "maceration"]
    }

    /// Words that qualify a process: "White Honey", "Double Anaerobic".
    static var processQualifiers: Set<String> {
        [
            "semi", "fully", "double", "triple", "thermal", "shock", "black", "red", "yellow", "white", "golden", "wet",
            "dry", "sun", "dried", "extended", "aerobic", "lactic", "yeast", "inoculated", "infused", "cold", "slow",
            "experimental",
        ]
    }
}
