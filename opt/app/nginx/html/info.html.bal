<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>用户信息 - 毕设系统</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 600px; margin: 50px auto; padding: 0 20px; }
        .header { margin-bottom: 30px; }
        .back-home { display: inline-block; padding: 8px 15px; background: #6c757d; color: white; text-decoration: none; border-radius: 4px; }
        .info-card { border: 1px solid #eee; border-radius: 8px; padding: 20px; }
        .info-item { margin: 15px 0; font-size: 16px; }
        .info-label { display: inline-block; width: 100px; color: #666; }
        .loading { text-align: center; padding: 50px; color: #666; }
    </style>
    <script src="https://cdn.bootcdn.net/ajax/libs/jquery/3.6.4/jquery.min.js"></script>
</head>
<body>
    <div class="header">
        <a href="index.html" class="back-home">返回主页</a>
        <h2 style="display: inline-block; margin-left: 20px;">用户信息详情</h2>
    </div>

    <div id="loading" class="loading">加载中...</div>
    <div id="infoCard" class="info-card" style="display: none;">
        <div class="info-item">
            <span class="info-label">用户名：</span>
            <span id="infoUsername"></span>
        </div>
        <div class="info-item">
            <span class="info-label">注册时间：</span>
            <span id="infoCreateTime"></span>
        </div>
        <div class="info-item">
            <span class="info-label">账户状态：</span>
            <span id="infoStatus">正常</span>
        </div>
        <div class="info-item">
            <span class="info-label">缓存状态：</span>
            <span id="infoCache">已缓存（Redis）</span>
        </div>
    </div>

    <script>
        $(function() {
            // 校验登录状态（未登录跳登录页）
            const username = localStorage.getItem("loginUsername");
            if (!username) {
                window.location.href = "login.html";
                return;
            }

            // 加载用户信息（调用后端查询接口）
            $.ajax({
                url: "/api/user/info", // 核心修改：加 /api 前缀（需后端新增该接口，见下方说明）
                method: "GET",
                data: { username: username },
                success: function(res) {
                    if (res.code === 200 && res.data) {
                        // 填充用户信息（后端返回数据适配）
                        $("#infoUsername").text(res.data.username || username);
                        $("#infoCreateTime").text(res.data.createTime || "2025-01-01");
                        // 隐藏加载，显示信息卡片
                        $("#loading").hide();
                        $("#infoCard").show();
                    } else {
                        $("#loading").text("用户信息加载失败");
                    }
                },
                error: function() {
                    $("#loading").text("接口请求失败");
                }
            });
        });
    </script>
</body>
</html>
