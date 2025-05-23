// (c) 2025 and onwards The vChewing Project (LGPL v3.0 License or later).
// ====================
// This code is released under the SPDX-License-Identifier: `LGPL-3.0-or-later`.

import Foundation

// MARK: - TrieSQLScriptGenerator

extension VanguardTrie {
  public enum TrieSQLScriptGenerator {
    // MARK: Public

    /// 將 Trie 結構匯出為 SQL 腳本
    /// - Parameters:
    ///   - trie: 要匯出的 Trie 結構
    /// - Returns: SQL 腳本內容。
    public static func generate(_ trie: VanguardTrie.Trie) -> String {
      var sqlCommands = [String]()

      // 設定優化參數，提高大量資料匯入速度
      sqlCommands.append("""
      -- 設定性能優化參數
      PRAGMA cache_size=10000;
      PRAGMA page_size=8192;
      PRAGMA temp_store=MEMORY;

      -- 取消日誌模式，因為原廠辭典資料是固定的
      PRAGMA journal_mode=OFF;
      PRAGMA synchronous=OFF;

      -- 開始事務
      BEGIN TRANSACTION;

      -- 移除現有表格
      DROP TABLE IF EXISTS keyinitials_id_map;
      DROP TABLE IF EXISTS nodes;
      DROP TABLE IF EXISTS config;

      -- 創建資料表結構
      CREATE TABLE config (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
      ) WITHOUT ROWID;

      CREATE TABLE nodes (
          id INTEGER PRIMARY KEY,
          reading_key TEXT DEFAULT '',
          entries_blob TEXT
      );

      -- 重新設計的 keyinitials_id_map 表，使用 JSON 存儲節點 ID 集合
      CREATE TABLE keyinitials_id_map (
          keyinitials TEXT PRIMARY KEY,
          node_ids TEXT NOT NULL
      ) WITHOUT ROWID;
      """)

      // 添加分隔符配置
      let escapedSeparator = String(trie.readingSeparator).replacingOccurrences(of: "'", with: "''")
      sqlCommands.append("-- 儲存分隔符設定")
      sqlCommands
        .append("INSERT INTO config (key, value) VALUES ('separator', '\(escapedSeparator)');")

      // 使用批量插入優化節點資料
      sqlCommands.append("-- 插入所有節點（包括根節點）")
      generateBatchNodeInserts(trie.nodes, into: &sqlCommands)

      // 批量插入 keyinitials_id_map 資料
      sqlCommands.append("-- 插入 keyinitials_id_map 資料")
      generateBatchKeychainIdMapInserts(trie.keyInitialsIDMap, into: &sqlCommands)

      // 提交事務，啟用外鍵約束
      sqlCommands.append("""
      -- 提交事務
      COMMIT;

      -- 啟用外鍵約束
      PRAGMA foreign_keys=ON;

      -- 創建索引
      CREATE INDEX IF NOT EXISTS idx_keyinitials_id_map_keyinitials ON keyinitials_id_map(keyinitials);
      CREATE INDEX IF NOT EXISTS idx_nodes_reading_key ON nodes(reading_key);
      CREATE INDEX IF NOT EXISTS idx_keyinitials_prefix ON keyinitials_id_map(keyinitials);

      -- 收集資料庫統計資訊，優化查詢
      ANALYZE;

      -- 整理資料庫，釋放未使用的空間
      VACUUM;
      """)

      return sqlCommands.joined(separator: "\n")
    }

    // MARK: Private

    /// 生成批量插入節點的 SQL 語句
    /// - Parameters:
    ///   - nodes: 節點辭典
    ///   - sqlCommands: SQL 命令數組，結果會添加到此數組
    private static func generateBatchNodeInserts(
      _ nodes: [Int: VanguardTrie.Trie.TNode],
      into sqlCommands: inout [String]
    ) {
      let batchSize = 500 // 每批插入的節點數量
      var nodeValues: [String] = []
      var count = 0

      // 處理所有節點（包括根節點）
      for (id, node) in nodes {
        // 正確處理所有字串以避免 SQL 注入和引號問題
        let escapedReadingKey = escapeSQLString(node.readingKey)

        // 將條目編碼為 base64 字串
        let entriesBlob = encodeEntriesToBase64(node.entries)
        let escapedEntriesBlob = escapeSQLString(entriesBlob)

        nodeValues
          .append(
            "(\(id), '\(escapedReadingKey)', '\(escapedEntriesBlob)')"
          )
        count += 1

        // 達到批處理大小或處理完所有節點時，生成一條批量插入語句
        if nodeValues.count >= batchSize || count == nodes.count {
          sqlCommands
            .append(
              "INSERT INTO nodes (id, reading_key, entries_blob) VALUES \(nodeValues.joined(separator: ","));"
            )
          nodeValues = []
        }
      }

      // 處理剩餘節點
      if !nodeValues.isEmpty {
        sqlCommands
          .append(
            "INSERT INTO nodes (id, reading_key, entries_blob) VALUES \(nodeValues.joined(separator: ","));"
          )
      }
    }

    /// 為 SQL 字串轉義，確保包含特殊字符（如分號）的字串能正確處理
    private static func escapeSQLString(_ input: String) -> String {
      // SQL 字串中單引號需要用兩個單引號表示
      input.replacingOccurrences(of: "'", with: "''")
    }

    /// 將條目陣列編碼為 base64 字串
    private static func encodeEntriesToBase64(_ entries: [VanguardTrie.Trie.Entry]) -> String {
      if entries.isEmpty { return "" }

      do {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(entries)
        return data.base64EncodedString()
      } catch {
        print("Error encoding entries: \(error)")
        return ""
      }
    }

    /// 生成批量插入 keyinitials_id_map 的 SQL 語句
    /// - Parameters:
    ///   - keyInitialsMap: keyInitialsIDMap 辭典
    ///   - sqlCommands: SQL 命令數組，結果會添加到此數組
    private static func generateBatchKeychainIdMapInserts(
      _ keyInitialsMap: [String: Set<Int>],
      into sqlCommands: inout [String]
    ) {
      let batchSize = 500 // 每批插入數量
      var keyInitialsValues: [String] = []

      // 遍歷所有 keyInitials 和對應的節點 ID Set
      for (keyInitials, nodeIDs) in keyInitialsMap {
        let escapedKeyInitials = escapeSQLString(keyInitials)
        // 將 Set<Int> 轉換為 JSON 字串
        let jsonData = try? JSONEncoder().encode(nodeIDs)
        if let jsonString = jsonData.map({ String(data: $0, encoding: .utf8) ?? "[]" }) {
          let escapedJsonString = escapeSQLString(jsonString)
          keyInitialsValues.append("('\(escapedKeyInitials)', '\(escapedJsonString)')")

          // 批量插入
          if keyInitialsValues.count >= batchSize {
            sqlCommands.append(
              "INSERT INTO keyinitials_id_map (keyinitials, node_ids) VALUES \(keyInitialsValues.joined(separator: ","));"
            )
            keyInitialsValues = []
          }
        }
      }

      // 處理剩餘資料
      if !keyInitialsValues.isEmpty {
        sqlCommands.append(
          "INSERT INTO keyinitials_id_map (keyinitials, node_ids) VALUES \(keyInitialsValues.joined(separator: ","));"
        )
      }
    }
  }
}
