package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gotd/td/telegram"
	"github.com/gotd/td/telegram/updates"
	"github.com/gotd/td/tg"
	"go.uber.org/zap"
	"gopkg.in/yaml.v3"

	"github.com/iyear/tdl/extension"
)

// 配置结构体
type Config struct {
	SubscriptionAPI struct {
		Host   string `yaml:"host"`
		ApiKey string `yaml:"api_key"`
	} `yaml:"subscription_api"`

	Features struct {
		FetchHistoryEnabled bool `yaml:"fetch_history_enabled"`
	} `yaml:"features"`

	Monitor struct {
		Channels          []int64 `yaml:"channels"`
		WhitelistChannels []int64 `yaml:"whitelist_channels"`
	} `yaml:"monitor"`

	Filters struct {
		Keywords      []string `yaml:"keywords"`
		ContentFilter []string `yaml:"content_filter"`
		LinkBlacklist []string `yaml:"link_blacklist"`
	} `yaml:"filters"`
}

// 全局配置变量
var config Config

// 加载配置文件
func loadConfig(filename string) error {
	data, err := os.ReadFile(filename)
	if err != nil {
		return fmt.Errorf("读取配置文件失败: %w", err)
	}

	if err := yaml.Unmarshal(data, &config); err != nil {
		return fmt.Errorf("解析配置文件失败: %w", err)
	}

	return nil
}

func main() {
	// 使用 extension.New 初始化扩展
	extension.New(extension.Options{
		// UpdateHandler 会在下面设置
	})(run)
}

func run(ctx context.Context, ext *extension.Extension) error {
	// 启动信息 - 同时输出到终端和日志
	fmt.Println("========================================")
	fmt.Println("🚀 tdl-msgwait 扩展启动中...")
	fmt.Printf("📂 数据目录: %s\n", ext.Config().DataDir)

	// 加载配置文件
	configPath := "config.yaml"
	// 尝试从扩展数据目录加载
	if ext.Config().DataDir != "" {
		configPath = ext.Config().DataDir + "/config.yaml"
	}

	fmt.Printf("📄 配置文件: %s\n", configPath)

	if err := loadConfig(configPath); err != nil {
		ext.Log().Error("配置文件加载失败", zap.Error(err))
		fmt.Printf("❌ 配置加载失败: %v\n", err)
		return fmt.Errorf("配置加载失败: %w", err)
	}

	fmt.Println("✅ 配置文件加载成功")
	fmt.Printf("📝 监听频道: %d 个\n", len(config.Monitor.Channels))
	fmt.Printf("📝 关键词: %d 个\n", len(config.Filters.Keywords))
	fmt.Printf("📝 白名单频道: %d 个\n", len(config.Monitor.WhitelistChannels))

	ext.Log().Info("✅ 配置文件加载成功")
	ext.Log().Info(fmt.Sprintf("📝 监听 %d 个频道", len(config.Monitor.Channels)))
	ext.Log().Info(fmt.Sprintf("📝 关键词数量: %d", len(config.Filters.Keywords)))
	ext.Log().Info(fmt.Sprintf("📝 白名单频道数量: %d", len(config.Monitor.WhitelistChannels)))

	// 创建 dispatcher 和 gaps
	dispatcher := tg.NewUpdateDispatcher()
	var dispatchCount int64

	// 添加消息处理包装器
	rawHandler := telegram.UpdateHandlerFunc(func(ctx context.Context, u tg.UpdatesClass) error {
		hasMessage := false
		switch update := u.(type) {
		case *tg.Updates:
			for _, upd := range update.Updates {
				switch upd.(type) {
				case *tg.UpdateNewMessage, *tg.UpdateNewChannelMessage, *tg.UpdateEditMessage, *tg.UpdateEditChannelMessage:
					hasMessage = true
					dispatchCount++
				}
			}
		case *tg.UpdateShortMessage, *tg.UpdateShortChatMessage:
			hasMessage = true
			dispatchCount++
		}

		if hasMessage {
			ext.Log().Info(fmt.Sprintf("收到消息更新 (#%d)", dispatchCount))
		}

		return dispatcher.Handle(ctx, u)
	})

	gaps := updates.New(updates.Config{
		Handler: rawHandler,
	})

	// 注册消息处理器
	dispatcher.OnNewMessage(func(ctx context.Context, e tg.Entities, update *tg.UpdateNewMessage) error {
		msg, ok := update.Message.(*tg.Message)
		if !ok {
			return nil
		}
		return handleMessage(ext, msg, e)
	})

	dispatcher.OnNewChannelMessage(func(ctx context.Context, e tg.Entities, update *tg.UpdateNewChannelMessage) error {
		msg, ok := update.Message.(*tg.Message)
		if !ok {
			return nil
		}
		return handleMessage(ext, msg, e)
	})

	dispatcher.OnEditMessage(func(ctx context.Context, e tg.Entities, update *tg.UpdateEditMessage) error {
		if msg, ok := update.Message.(*tg.Message); ok {
			return handleMessage(ext, msg, e)
		}
		return nil
	})

	dispatcher.OnEditChannelMessage(func(ctx context.Context, e tg.Entities, update *tg.UpdateEditChannelMessage) error {
		if msg, ok := update.Message.(*tg.Message); ok {
			return handleMessage(ext, msg, e)
		}
		return nil
	})

	// 获取 API 客户端
	api := ext.Client().API()

	// 获取当前用户信息
	self, err := api.UsersGetUsers(ctx, []tg.InputUserClass{&tg.InputUserSelf{}})
	if err != nil {
		return fmt.Errorf("获取用户信息失败: %w", err)
	}

	user := self[0].(*tg.User)
	fmt.Printf("👤 当前用户: %s %s (ID: %d)\n", user.FirstName, user.LastName, user.ID)
	ext.Log().Info(fmt.Sprintf("👤 当前用户: %s %s (ID: %d)", user.FirstName, user.LastName, user.ID))

	// 获取历史消息（如果启用）
	if config.Features.FetchHistoryEnabled && len(config.Monitor.Channels) > 0 {
		fmt.Println("📜 开始获取历史消息...")
		ext.Log().Info("📜 开始获取历史消息...")
		for _, channelID := range config.Monitor.Channels {
			if err := fetchChannelHistory(ctx, ext, api, channelID); err != nil {
				fmt.Printf("⚠️ 获取频道 %d 历史消息失败: %v\n", channelID, err)
				ext.Log().Warn(fmt.Sprintf("⚠️ 获取频道 %d 历史消息失败: %v", channelID, err))
			}
		}
		fmt.Println("✅ 历史消息获取完成")
		ext.Log().Info("✅ 历史消息获取完成")
	}

	// 启动监听
	fmt.Println("========================================")
	fmt.Println("👂 开始监听实时消息...")
	fmt.Println("⏳ 等待新消息中... (按 Ctrl+C 退出)")
	fmt.Println("========================================")
	ext.Log().Info("👂 开始监听实时消息...")
	ext.Log().Info("⏳ 等待新消息中...")

	// 启动心跳检测
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		startTime := time.Now()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				uptime := time.Since(startTime).Round(time.Second)
				fmt.Printf("💓 心跳 | 运行: %v | 已处理消息: %d\n", uptime, dispatchCount)
				ext.Log().Info(fmt.Sprintf("运行:%v | 消息:%d", uptime, dispatchCount))
			}
		}
	}()

	// 运行 gaps
	ext.Log().Info(fmt.Sprintf("🚀 启动消息监听 (UserID: %d)", user.ID))

	return gaps.Run(ctx, api, user.ID, updates.AuthOptions{
		IsBot: user.Bot,
		OnStart: func(ctx context.Context) {
			ext.Log().Info("✅ 开始接收实时更新")
		},
	})
}

// handleMessage 处理消息并检查关键词
func handleMessage(ext *extension.Extension, msg *tg.Message, e tg.Entities) error {
	messageText := msg.Message

	// 频道过滤检查
	var channelID int64
	if msg.PeerID != nil {
		if peer, ok := msg.PeerID.(*tg.PeerChannel); ok {
			channelID = peer.ChannelID
		}
	}

	// 如果配置了监听频道列表,则只处理这些频道的消息
	if len(config.Monitor.Channels) > 0 {
		allowedChannel := false
		for _, id := range config.Monitor.Channels {
			if id == channelID {
				allowedChannel = true
				break
			}
		}
		if !allowedChannel {
			return nil
		}
	}

	// 关键词匹配
	matched := false
	for _, keyword := range config.Filters.Keywords {
		if strings.Contains(strings.ToLower(messageText), strings.ToLower(keyword)) {
			matched = true
			break
		}
	}

	if !matched {
		return nil
	}

	// 检查是否在白名单中
	isWhitelisted := false
	for _, whiteID := range config.Monitor.WhitelistChannels {
		if whiteID == channelID {
			isWhitelisted = true
			break
		}
	}

	// 如果不在白名单中,需要进行二次过滤
	if !isWhitelisted {
		contentMatched := false
		for _, filterWord := range config.Filters.ContentFilter {
			if strings.Contains(messageText, filterWord) {
				contentMatched = true
				break
			}
		}

		if !contentMatched {
			return nil
		}
	}

	// 提取消息中的链接
	links := extractLinks(messageText)

	// 只显示提取到的链接
	if len(links) > 0 {
		var source string
		if msg.PeerID != nil {
			switch peer := msg.PeerID.(type) {
			case *tg.PeerChannel:
				source = fmt.Sprintf("频道:%d", peer.ChannelID)
			case *tg.PeerChat:
				source = fmt.Sprintf("群组:%d", peer.ChatID)
			case *tg.PeerUser:
				source = fmt.Sprintf("私聊:%d", peer.UserID)
			}
		}

		for _, link := range links {
			fmt.Printf("[%s] %s | %s\n",
				time.Now().Format("15:04:05"),
				source,
				link)

			// 自动添加订阅链接
			success, message := addSubscription(link)
			if success {
				fmt.Printf("  ✅ 订阅添加成功: %s\n", message)
			} else {
				if message == "订阅已存在" {
					fmt.Printf("  ⚠️  订阅已存在，跳过\n")
				} else {
					fmt.Printf("  ❌ 订阅添加失败: %s\n", message)
				}
			}
		}
	}

	return nil
}

// extractLinks 从文本中提取所有链接
func extractLinks(text string) []string {
	var links []string
	lines := strings.Split(text, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.Contains(line, "http://") || strings.Contains(line, "https://") {
			remainingLine := line
			for len(remainingLine) > 0 {
				httpIdx := strings.Index(remainingLine, "http://")
				httpsIdx := strings.Index(remainingLine, "https://")

				startIdx := -1
				if httpIdx >= 0 && httpsIdx >= 0 {
					startIdx = min(httpIdx, httpsIdx)
				} else if httpIdx >= 0 {
					startIdx = httpIdx
				} else if httpsIdx >= 0 {
					startIdx = httpsIdx
				}

				if startIdx < 0 {
					break
				}

				linkStart := startIdx
				linkEnd := linkStart
				for linkEnd < len(remainingLine) {
					ch := remainingLine[linkEnd]
					if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
						break
					}
					linkEnd++
				}

				link := remainingLine[linkStart:linkEnd]
				link = strings.TrimRight(link, ",.;!?，。；！？、")

				isBlacklisted := false
				linkLower := strings.ToLower(link)
				for _, blackword := range config.Filters.LinkBlacklist {
					if strings.Contains(linkLower, strings.ToLower(blackword)) {
						isBlacklisted = true
						break
					}
				}

				if !isBlacklisted && len(link) > 8 {
					links = append(links, link)
				}

				remainingLine = remainingLine[linkEnd:]
			}
		}
	}
	return links
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// fetchChannelHistory 获取指定频道的历史消息
func fetchChannelHistory(ctx context.Context, ext *extension.Extension, api *tg.Client, channelID int64) error {
	ext.Log().Info(fmt.Sprintf("📥 正在获取频道 %d 的历史消息...", channelID))

	inputPeer := &tg.InputPeerChannel{
		ChannelID:  channelID,
		AccessHash: 0,
	}

	// 尝试从对话中查找 AccessHash
	dialogs, err := api.MessagesGetDialogs(ctx, &tg.MessagesGetDialogsRequest{
		OffsetDate: 0,
		OffsetID:   0,
		OffsetPeer: &tg.InputPeerEmpty{},
		Limit:      100,
		Hash:       0,
	})

	if err != nil {
		return fmt.Errorf("获取对话列表失败: %w", err)
	}

	var foundChannel *tg.Channel
	switch d := dialogs.(type) {
	case *tg.MessagesDialogs:
		for _, chat := range d.Chats {
			if ch, ok := chat.(*tg.Channel); ok && ch.ID == channelID {
				foundChannel = ch
				break
			}
		}
	case *tg.MessagesDialogsSlice:
		for _, chat := range d.Chats {
			if ch, ok := chat.(*tg.Channel); ok && ch.ID == channelID {
				foundChannel = ch
				break
			}
		}
	}

	if foundChannel == nil {
		return fmt.Errorf("未找到频道 %d", channelID)
	}

	ext.Log().Info(fmt.Sprintf("📢 频道名称: %s", foundChannel.Title))
	inputPeer.AccessHash = foundChannel.AccessHash

	// 获取历史消息
	history, err := api.MessagesGetHistory(ctx, &tg.MessagesGetHistoryRequest{
		Peer:  inputPeer,
		Limit: 100,
		Hash:  0,
	})

	if err != nil {
		return fmt.Errorf("获取历史消息失败: %w", err)
	}

	var messages []tg.MessageClass
	switch h := history.(type) {
	case *tg.MessagesMessages:
		messages = h.Messages
	case *tg.MessagesMessagesSlice:
		messages = h.Messages
	case *tg.MessagesChannelMessages:
		messages = h.Messages
	}

	ext.Log().Info(fmt.Sprintf("📊 获取到 %d 条历史消息", len(messages)))

	matchCount := 0
	for i := len(messages) - 1; i >= 0; i-- {
		msg, ok := messages[i].(*tg.Message)
		if !ok {
			continue
		}

		messageText := msg.Message
		if messageText == "" {
			continue
		}

		matched := false
		for _, keyword := range config.Filters.Keywords {
			if strings.Contains(strings.ToLower(messageText), strings.ToLower(keyword)) {
				matched = true
				break
			}
		}

		if !matched {
			continue
		}

		isWhitelisted := false
		for _, whiteID := range config.Monitor.WhitelistChannels {
			if whiteID == channelID {
				isWhitelisted = true
				break
			}
		}

		if !isWhitelisted {
			contentMatched := false
			for _, filterWord := range config.Filters.ContentFilter {
				if strings.Contains(messageText, filterWord) {
					contentMatched = true
					break
				}
			}

			if !contentMatched {
				continue
			}
		}

		links := extractLinks(messageText)

		if len(links) > 0 {
			msgTime := time.Unix(int64(msg.Date), 0).Format("2006-01-02 15:04:05")

			for _, link := range links {
				fmt.Printf("[%s] 频道:%d | %s\n", msgTime, channelID, link)

				success, message := addSubscription(link)
				if success {
					fmt.Printf("  ✅ 订阅添加成功: %s\n", message)
				} else {
					if message == "订阅已存在" {
						fmt.Printf("  ⚠️  订阅已存在，跳过\n")
					} else {
						fmt.Printf("  ❌ 订阅添加失败: %s\n", message)
					}
				}
			}

			matchCount++
		}
	}

	ext.Log().Info(fmt.Sprintf("✅ 频道 %d: 匹配到 %d 条消息", channelID, matchCount))
	return nil
}

// addSubscription 添加订阅链接到订阅管理系统
// 参数: subURL - 订阅链接
// 返回: (成功, 消息)
func addSubscription(subURL string) (bool, string) {
	// 构建请求体
	requestBody := map[string]string{
		"sub_url": subURL,
	}

	jsonData, err := json.Marshal(requestBody)
	if err != nil {
		return false, fmt.Sprintf("JSON 编码失败: %v", err)
	}

	// 创建 HTTP 客户端，设置超时
	client := &http.Client{
		Timeout: 10 * time.Second,
	}

	// 构建请求
	apiURL := fmt.Sprintf("http://%s/api/config/add", config.SubscriptionAPI.Host)
	req, err := http.NewRequest("POST", apiURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return false, fmt.Sprintf("创建请求失败: %v", err)
	}

	// 设置请求头
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-API-Key", config.SubscriptionAPI.ApiKey)

	// 发送请求
	resp, err := client.Do(req)
	if err != nil {
		return false, fmt.Sprintf("API 请求失败: %v", err)
	}
	defer resp.Body.Close()

	// 读取响应
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return false, fmt.Sprintf("读取响应失败: %v", err)
	}

	// 检查状态码
	if resp.StatusCode != http.StatusOK {
		return false, fmt.Sprintf("API 返回错误状态码 %d: %s", resp.StatusCode, string(body))
	}

	// 解析响应
	var result struct {
		Message string `json:"message"`
		Error   string `json:"error"`
	}

	if err := json.Unmarshal(body, &result); err != nil {
		return false, fmt.Sprintf("解析响应失败: %v", err)
	}

	// 检查是否是重复订阅
	if result.Error != "" {
		if strings.Contains(result.Error, "已存在") || strings.Contains(strings.ToLower(result.Error), "already exists") {
			return false, "订阅已存在"
		}
		return false, result.Error
	}

	return true, result.Message
}
