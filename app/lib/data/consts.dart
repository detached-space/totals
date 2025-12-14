class Bank {
  final int id;
  final String name;
  final String shortName;
  final List<String> codes;
  final String image;

  const Bank({
    required this.id,
    required this.name,
    required this.shortName,
    required this.codes,
    required this.image,
  });
}

class AppConstants {
  static const List<Bank> banks = [
    Bank(
      id: 1,
      name: "Commercial Bank Of Ethiopia",
      shortName: "CBE",
      codes: [
        "CBE",
      ],
      image: "assets/images/cbe.png",
    ),
    Bank(
      id: 2,
      name: "Awash Bank",
      shortName: "Awash",
      codes: [
        "Awash",
        "Awash Bank",
      ],
      image: "assets/images/awash.png",
    ),
    Bank(
      id: 3,
      name: "Bank Of Abyssinia",
      shortName: "BOA",
      codes: [
        "BOA",
      ],
      image: "assets/images/boa.png",
    ),
    Bank(
      id: 4,
      name: "Dashen Bank",
      shortName: "Dashen",
      codes: [
        "Dashen",
        "Dashen Bank",
      ],
      image: "assets/images/dashen.png",
    ),
    Bank(
      id: 6,
      name: "Telebirr",
      shortName: "Telebirr",
      codes: [
        "127",
      ],
      image: "assets/images/telebirr.png",
    ),
  ];
}
