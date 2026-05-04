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
        "DashenBank",
        "Dashen Bank",
      ],
      image: "assets/images/dashen.png",
    ),
    Bank(
      id: 5,
      name: "Zemen Bank",
      shortName: "Zemen",
      codes: [
        "Zemen Bank",
        "Zemen",
      ],
      image: "assets/images/zemen.png",
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
    Bank(
      id: 8,
      name: "M Pesa",
      shortName: "MPESA",
      codes: [
        "MPESA",
        "M-Pesa",
        "Mpesa",
      ],
      image: "assets/images/mpesa.png",
    ),
    Bank(
      id: 9,
      name: "Amhara Bank",
      shortName: "Aba",
      codes: [
        "Amhara Bank",
        "Amhara",
        "AmharaBank",
      ],
      image: "assets/images/amhara.png",
    ),
    Bank(
      id: 10,
      name: "Ahadu Bank",
      shortName: "Ahadu",
      codes: [
        "Ahadu Bank",
        "Ahadu",
      ],
      image: "assets/images/ahadu.png",
    ),
    Bank(
      id: 12,
      name: "Berhan Bank",
      shortName: "Berhan",
      codes: [
        "Berhan Bank",
        "Berhan",
      ],
      image: "assets/images/berhan.png",
    ),
    Bank(
      id: 13,
      name: "Bunna Bank",
      shortName: "Bunna",
      codes: [
        "Bunna Bank",
        "Bunna",
      ],
      image: "assets/images/bunna.png",
    ),
    Bank(
      id: 14,
      name: "Cooperative Bank of Oromia",
      shortName: "CBO",
      codes: [
        "COOPayEBIRR",
        "COOP",
        "CBO",
        "Coop",
      ],
      image: "assets/images/coop.png",
    ),
    Bank(
      id: 19,
      name: "Hibret Bank",
      shortName: "Hibret",
      codes: [
        "HibretBank",
        "Hibret Bank",
        "Hibret",
      ],
      image: "assets/images/hibret.png",
    ),
    Bank(
      id: 24,
      name: "Oromia Bank",
      shortName: "Oromia",
      codes: [
        "Oromia Bank",
        "Oromia",
        "OIB",
      ],
      image: "assets/images/oromia.png",
    ),
    Bank(
      id: 30,
      name: "Tsedey Bank",
      shortName: "Tsedey",
      codes: [
        "Tsedey Bank",
        "Tsedey",
      ],
      image: "assets/images/tsedey.png",
    ),
    Bank(
      id: 33,
      name: "Wegagen Bank",
      shortName: "Wegagen",
      codes: [
        "WegagenBank",
        "Wegagen Bank",
        "Wegagen",
      ],
      image: "assets/images/wegagen.png",
    ),
    Bank(
      id: 36,
      name: "Apollo",
      shortName: "Apollo",
      codes: [
        "apollo",
        "Apollo",
      ],
      image: "assets/images/apollo.png",
    ),
    Bank(
      id: 37,
      name: "CBE Birr",
      shortName: "CBEBirr",
      codes: [
        "CBEBirr",
        "CBE Birr",
      ],
      image: "assets/images/cbe_birr.png",
    ),
  ];
}
