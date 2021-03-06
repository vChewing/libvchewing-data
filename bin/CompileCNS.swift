// 該檔案用來將全字庫 OpenData 當中的資料轉成可以交給 libvchewing-data 編譯的那種原始資料格式。

import Foundation

var pathCNS2UTF_1: String = "./Open_Data/MapingTables/Unicode/CNS2UNICODE_Unicode BMP.txt"
var pathCNS2UTF_2: String = "./Open_Data/MapingTables/Unicode/CNS2UNICODE_Unicode 15.txt"
var pathCNS2UTF_3: String = "./Open_Data/MapingTables/Unicode/CNS2UNICODE_Unicode 2.txt"
var pathIDG2PNB: String = "./Open_Data/Properties/CNS_phonetic.txt"

var dicCNS2UTF: [String: String] = .init()
var strIDG2PNB: String = ""
do {
  let strCNS2UTF: String =
    try String(contentsOfFile: pathCNS2UTF_1, encoding: .utf8) + "\n"
    + String(contentsOfFile: pathCNS2UTF_2, encoding: .utf8) + "\n"
    + String(contentsOfFile: pathCNS2UTF_3, encoding: .utf8)
  strIDG2PNB = try String(contentsOfFile: pathIDG2PNB, encoding: .utf8)
  var currentLine = ""
  for line in strCNS2UTF.split(separator: "\n") {
    currentLine = String(line)
    let fields = currentLine.split(separator: "\t")
    guard fields.count == 2 else {
      print("////" + line)
      continue
    }
    let charInt = UInt32(String(fields[1]), radix: 16) ?? 0
    if let scalar = UnicodeScalar(charInt) {
      dicCNS2UTF[String(fields[0])] = String(Character(scalar))
    }
  }
} catch {
  print(error)
}

print(dicCNS2UTF.count)

var currentLine: String = ""
var strOutput: String = ""
var arrIDG2PNB = strIDG2PNB.split(separator: "\n")
let locale = Locale(identifier: "zh-Hant-TW")
arrIDG2PNB = arrIDG2PNB.sorted {
  $0.compare($1, locale: locale) == .orderedAscending
}

for line in arrIDG2PNB {
  currentLine = String(line)
  let fields = currentLine.split(separator: "\t")
  guard fields.count == 2 else {
    print("$$$$$$" + line)
    continue
  }
  guard let char = dicCNS2UTF[String(fields[0])] else {
    continue
  }
  strOutput += char + " " + String(fields[1]) + "\n"
}

do {
  try strOutput.write(toFile: "./Output.txt", atomically: true, encoding: .utf8)
} catch {
  print("Error when writing output file.")
}

print("Process completed.")
