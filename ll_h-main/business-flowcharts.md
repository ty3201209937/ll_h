# H 换电柜业务流程图

本文档根据当前工程代码整理，入口为 `main.lua`。图中的“上报”表示通过 TCP 或 TCP-S 发送到服务器；BLE 流程使用 `ble_server.lua` 的 JSON 协议；仓门、充电器和仓控板动作最终都通过 `can_bus.lua` 下发 CAN。

## 1. 系统总览

```mermaid
flowchart TD
    A[main.lua 启动] --> B[加载 sys / user / ble_server]
    B --> C[sys.run 调度]
    C --> D[user_poll 主循环]
    C --> E[CAN 接收与发送任务]
    C --> F[TCP-N 网络任务]
    C --> G[TCP-S 串口/备用链路任务]
    C --> H[BLE 主任务]

    D --> D1[monitor_poll 监控轮询]
    D --> D2[abnor_poll / abnor_check 异常处理]
    D --> D3[batinfo_update_poll 电池识别与自动充电]
    D --> D4[bat_exchange 换电状态机]
    D --> D5[bat_return 退电状态机]
    D --> D6[bat_charge 充电入仓状态机]
    D --> D7[bat_quout 取电状态机]

    F --> I[服务器下发二进制指令]
    G --> I
    H --> J[手机 JSON 指令]
    I --> K{业务互斥检查}
    J --> K
    K -->|Exchanging| D4
    K -->|ReturnBating| D5
    K -->|ChargeBating| D6
    K -->|QuBating| D7

    E --> L[CAN 状态回包]
    L --> M[attr 运行时缓存]
    M --> D
    M --> N[TCP/BLE 状态上报]
    D --> O[can_bus.charging / locking / reqbox]
    O --> E
```

**核心代码：** `main.lua`；`user/user.lua:user_poll`、`user_init`；`user/can_bus.lua:rece_process/send_process`。

## 2. 启动、初始化和断电恢复

```mermaid
flowchart TD
    A[系统启动] --> B[attr.init]
    B --> C[从 fskv 恢复 SETUP、BT、异常和订单信息]
    C --> D[逐仓恢复已保存 BT 并调用 analysis_bt]
    D --> E{Exbat_Info.flag 且 orderget?}
    E -->|是| E1[Exbat_State=true<br/>Re_Exbat=true<br/>发布 Exchanging]
    E -->|否| F{Rebat_Info.flag 且 number?}
    E1 --> F
    F -->|是且当前无换电| F1[Rebat_State=true<br/>Re_Rebat=true<br/>发布 ReturnBating]
    F -->|是但当前忙| F2[上报退电被占用]
    F -->|否| G{Chbat_Info.flag 且 number?}
    F1 --> G
    F2 --> G
    G -->|是且无换电/退电| G1[Chbat_State=true<br/>Re_Chbat=true<br/>发布 ChargeBating]
    G -->|冲突| G2[按冲突业务上报失败]
    G1 --> H{Qubat_Info.flag 且 number?}
    G2 --> H
    H -->|是且无其他业务| H1[Qubat_State=true<br/>Re_Qubat=true<br/>发布 QuBating]
    H -->|冲突| H2[按冲突业务上报失败]
    H1 --> I[初始化 TCP、CAN、音频、LCD、异常任务]
    H2 --> I
    I --> J[user_poll 每100ms轮询]
```

订单的持久信息：

- TCP 旧业务：`Exbat_Info`、`Rebat_Info`、`Chbat_Info`、`Qubat_Info`，使用 `attr.*_info_set` 写入 `fskv`。
- BLE JSON 业务：`BLESwapOrders` 索引和逐笔记录，保存订单参数、阶段、结果和实际 BT 码，供重连查询和防重复开门。

**源码：** `user/user.lua:user_init`；`user/attr.lua:attr.init`、`attr.exbat_info_set`；`user/ble_swap_orders.lua`。

## 3. TCP 指令接入和业务分发

```mermaid
flowchart TD
    A[TCP 收到完整帧] --> B[class_process / recv_process]
    B --> C{帧类型}
    C -->|0x06 ExchangeBat| D[解析回收仓、回收BT、释放仓、释放BT、订单号、锁标志]
    C -->|0x20 ReturnBat| E[解析退电订单]
    C -->|0x27 ChargeBat| F[解析充电入仓仓号、BT、订单号]
    C -->|0x2A QuBat| G[解析取电订单]
    C -->|0x0E Charging| H[解析人工充电开关、电压、电流]
    C -->|0x19 Delete| I[清除仓信息]
    C -->|其他控制类| J[开门、禁仓、风扇、升级、报警等]

    D --> D1{仓号/BT/长度有效?}
    D1 -->|否| D2[拒绝并上报错误]
    D1 -->|是| X{Exbat/Rebat/Chbat/Qubat/升级状态?}
    X -->|忙| X1[返回重复、占用或冲突结果]
    X -->|空闲| X2[attr.exbat_info_set(true, ...)<br/>写 Exbat_Info]
    X2 --> X3[发布 Exchanging]

    E --> E1{空闲且参数有效?}
    E1 -->|是| E2[保存 Rebat_Info<br/>发布 ReturnBating]
    E1 -->|否| E3[返回冲突/参数错误]
    F --> F1{业务空闲且仓号/BT有效?}
    F1 -->|是| F2[保存 Chbat_Info<br/>发布 ChargeBating]
    F1 -->|否| F3[返回冲突/参数错误]
    G --> G1{业务空闲且仓号有效?}
    G1 -->|是| G2[保存 Qubat_Info<br/>发布 QuBating]
    G1 -->|否| G3[返回冲突/参数错误]
    H --> H1[can_bus.charging 开启或关闭<br/>更新 C_Chg 位图]
    I --> I1[attr.bat_clean<br/>清理本仓 BT、SOC、电压等缓存]
```

`0x19 Delete` 是“清除仓信息”，不是普通状态读取。执行后 `attr.bat_BT_get(order)` 为空，之后 `batinfo_upload` 会用 `FF` 填充 BT 字段。

**源码：** `user/tcp_net.lua:class_process`、`user/tcp_net.lua` 的 `CLASS.ExchangeBat/ChargeBat/Delete` 分支；`user/tcp_s.lua` 有对应的 TCP-S 分支。

## 4. BLE JSON 接入、握手和快照

```mermaid
flowchart TD
    A[手机连接 BLE] --> B[EVENT_CONN]
    B --> C[清空接收缓冲、发送队列和传输去重缓存]
    C --> D[手机向 EA02 分片写入 JSON 行]
    D --> E[receive_data 按 LF 重组完整报文]
    E --> F{cmd=connect?}
    F -->|否| G{会话已建立?}
    F -->|是| H{device_id 和 protocol_version=2.1.0?}
    H -->|否| H1[ack code=4/8<br/>不建立业务会话]
    H -->|是| H2[生成 challenge<br/>发送 ack + device_info]
    H2 --> I[手机 ack device_info]
    I --> J[手机 snapshot_get]
    J --> K{snapshot_id、会话、字段有效?}
    K -->|否| K1[返回错误 ack]
    K -->|是| L[reqbox 询问所有仓控板]
    L --> M[刷新状态序号、485 BT、模拟量]
    M --> N[发送 status]
    N --> O[每仓 slot_status + battery_status]
    O --> P[发送 board_version 队列]
    P --> Q[发送 snapshot_end]
    Q --> R{手机 ack snapshot_end?}
    R -->|否| R1[关键消息按策略重发]
    R -->|是| R2[快照批次完成<br/>再发送 board_version]

    G -->|否| G1[ack code=7]
    G -->|是| S{cmd=snapshot_get/swap/swap_query/ack?}
    S -->|swap| T[字段校验 -> 签名校验 -> 释放仓实时复核]
    S -->|swap_query| U[查询 BLESwapOrders<br/>返回 swap_state/result]
    S -->|ack| V[确认 pending 消息]
```

快照仓位数据来源：

```mermaid
flowchart LR
    A[CAN reqbox(slot,1)] --> B[仓控状态回包]
    B --> C[门锁、485在线、仓电压、仓温度]
    A --> D[485 BT 分片回包]
    D --> E[Bat_BT_485]
    A --> F[模拟量/电池电压/SOC回包]
    F --> G[Bat_Vol、Bat_Cur、Bat_Power]
    C --> H[slot_status]
    E --> I[battery_status.bt_code]
    G --> I
    J[持久 bat_BT_get] -.仅诊断/历史绑定.-> I
    I --> K{当前采样有效?}
    K -->|是| L[发送实时值]
    K -->|否| M[发送 JSON null]
```

**源码：** `user/ble_server.lua:receive_data`、`handle_message`、`snapshot`、`refresh_snapshot_slots`；`user/ble_swap_orders.lua:refresh_release/refresh_return`。

## 5. BLE/TCP 换电受理和执行

```mermaid
flowchart TD
    A[收到换电订单] --> B{字段、仓号、BT、SOC阈值有效?}
    B -->|否| B1[ack=1 invalid fields]
    B -->|是| C{BLE签名有效?}
    C -->|否| C1[ack=9<br/>不登记、不开门]
    C -->|是或TCP路径| D{同 order_id 已存在?}
    D -->|同参数| D1[ack=0<br/>返回原状态/结果<br/>不重复开门]
    D -->|参数冲突| D2[ack=6]
    D -->|不存在| E{柜机当前空闲?}
    E -->|否| E1[ack=3 cabinet busy]
    E -->|是| F[刷新释放仓 CAN 数据]
    F --> G{释放仓有485、BT匹配、SOC达标、未禁用、无异常?}
    G -->|否| G1[ack=7<br/>不登记、不执行]
    G -->|是| H[保存订单 accepted]
    H --> I[写入 Exbat_Info / BLE order record]
    I --> J{写入成功?}
    J -->|否| J1[ack=5 persistence failed]
    J -->|是| K[设置 Exbat_State=true<br/>发布 Exchanging]
    K --> L[ack=0 accepted]
    L --> M[bat_exchange 状态机]
```

## 6. 换电状态机 `bat_exchange`

```mermaid
stateDiagram-v2
    [*] --> INIT: Exchanging
    INIT: 读取 Exbat_Info<br/>回收仓 order_get<br/>释放仓 order_give<br/>BLE 读取持久订单
    INIT --> RESTART_RECOVER: Re_Exbat
    INIT --> PRECHECK: 普通启动

    RESTART_RECOVER: 重新询问两个仓<br/>根据门、485、BT、电压恢复
    RESTART_RECOVER --> WAIT_RETURN_CLOSE: 回收门已关且状态稳定
    RESTART_RECOVER --> RETURN_FLOW: 回收门未关或需要继续回收
    RESTART_RECOVER --> RELEASE_WAIT: BLE 已完成回收，等待取走释放电池
    RESTART_RECOVER --> RECOVERY: 身份或释放状态无法确认

    PRECHECK: 等待回收仓和释放仓门关闭、485状态有效
    PRECHECK --> CLOSE_ALL: 初始状态完成
    CLOSE_ALL: ex_state=-2<br/>判断所有未禁用仓是否关门
    CLOSE_ALL --> OPEN_RETURN_PREP: BLE实时刷新回收仓为空
    CLOSE_ALL --> VALIDATE_RETURN_ALREADY: 回收仓已有订单BT
    CLOSE_ALL --> FAIL_OCCUPIED: 回收仓检测到其他BT或电压
    CLOSE_ALL --> FAIL_TIMEOUT: 30秒未关闭全部仓门

    OPEN_RETURN_PREP: ex_state=0<br/>停止回收仓充电<br/>locking(order_get)
    OPEN_RETURN_PREP --> WAIT_RETURN_DOOR: 门反馈打开
    OPEN_RETURN_PREP --> OPEN_RETURN_PREP: 未打开且重试次数未超限
    OPEN_RETURN_PREP --> FAIL_OPEN_RETURN: 重试耗尽

    WAIT_RETURN_DOOR: ex_state=1<br/>等待回收仓关门
    WAIT_RETURN_DOOR --> WAIT_RETURN_BATTERY: 门已关闭
    WAIT_RETURN_DOOR --> FAIL_CLOSE_RETURN: 超时

    WAIT_RETURN_BATTERY: ex_state=2<br/>等待485 BT/电压识别
    WAIT_RETURN_BATTERY --> VALIDATE_RETURN: 检测到电池
    WAIT_RETURN_BATTERY --> WAIT_RETURN_BATTERY: 低电电池补充或再次开门
    WAIT_RETURN_BATTERY --> FAIL_NO_RETURN: 重试/超时耗尽

    VALIDATE_RETURN: ex_state=3<br/>核对回收BT
    VALIDATE_RETURN --> RELEASE_CHECK: BLE实际BT匹配订单BT
    VALIDATE_RETURN --> RELEASE_CHECK: TCP BT匹配订单BT
    VALIDATE_RETURN --> FAIL_RETURN_MISMATCH: BT不匹配
    RELEASE_CHECK: BLE刷新释放仓<br/>核对释放BT、SOC、门、禁用、异常
    RELEASE_CHECK --> OPEN_RELEASE: 条件通过
    RELEASE_CHECK --> FAIL_RELEASE_NOT_READY: 条件不通过

    OPEN_RELEASE: ex_state=4<br/>locking(order_give)
    OPEN_RELEASE --> WAIT_RELEASE_TAKE: 门确认打开
    OPEN_RELEASE --> COMPLETE_TCP: TCP旧流程按门打开上报成功
    OPEN_RELEASE --> FAIL_OPEN_RELEASE: 重试耗尽

    WAIT_RELEASE_TAKE: ex_state=5<br/>BLE等待释放电池被取走
    WAIT_RELEASE_TAKE --> COMPLETE_BLE: 485关闭/电压消失确认取走
    WAIT_RELEASE_TAKE --> FAIL_RELEASE_STILL_PRESENT: 超时且电池仍在仓
    WAIT_RELEASE_TAKE --> RECOVERY: 状态不明

    COMPLETE_BLE: 持久化终态 -> 上报26 -> 清理释放仓缓存 -> 启动回收仓首次充电
    COMPLETE_TCP: 上报26/27等结果 -> 等TCP ACK -> 清空 Exbat_Info
    FAIL_OCCUPIED --> [*]
    FAIL_TIMEOUT --> [*]
    FAIL_OPEN_RETURN --> [*]
    FAIL_CLOSE_RETURN --> [*]
    FAIL_NO_RETURN --> [*]
    FAIL_RETURN_MISMATCH --> [*]
    FAIL_RELEASE_NOT_READY --> [*]
    FAIL_OPEN_RELEASE --> [*]
    FAIL_RELEASE_STILL_PRESENT --> [*]
    RECOVERY: BLE_SWAP_STAGE=recovery_required<br/>不自动重复开门
```

关键动作：

- `ex_state=-2`：先确保所有相关仓门关闭，再用 BLE 新鲜采样判断回收仓是否为空，避免用旧 `bat_BT_get` 误判。
- `ex_state=0`：打开回收仓；门反馈为 `Box_Lock[order_get] == 0` 才算打开。
- `ex_state=1/2`：等待关门并识别放入电池。
- `ex_state=3`：核对回收 BT；BLE 还会在打开释放门前实时复核释放仓身份和 SOC。
- `ex_state=4`：打开释放仓。BLE 在 `ex_state=5` 等待真实取走确认后才完成。

**源码：** `user/user.lua:bat_exchange`，`user/ble_swap_orders.lua:release_ready/refresh_release/refresh_return`。

## 7. 退电流程 `bat_return`

```mermaid
flowchart TD
    A[ReturnBating] --> B[读取 Rebat_Info]
    B --> C{重启恢复?}
    C -->|是| D[reqbox 回收仓<br/>恢复门/电池状态]
    C -->|否| E[等待回收仓和释放仓初始状态]
    D --> F
    E --> F{re_state=-1: 所有仓关闭?}
    F -->|否| F1[超时上报1]
    F -->|是| G{回收仓已有BT/电压?}
    G -->|是| G1[上报占用/已有电池错误]
    G -->|否| H[re_state=0<br/>打开回收仓]
    H --> I{门打开?}
    I -->|否且未超时| H
    I -->|否且超时| I1[上报开门失败2]
    I -->|是| J[re_state=1<br/>等待关门]
    J --> K{门关闭?}
    K -->|否且未超时| J
    K -->|否且超时| K1[上报关门失败3]
    K -->|是| L[re_state=2<br/>识别放入 BT/电压]
    L --> M{检测到电池?}
    M -->|否| M1[再次开门或上报4/0x0A]
    M -->|是| N{BT/电压与订单匹配?}
    N -->|否| N1[上报5或9并清理]
    N -->|是| O[上报1A/1B<br/>进入充电或结束退电]
    O --> P[清理状态、上传仓/电池信息]
```

**源码：** `user/user.lua:bat_return`，订单入口为 `user/tcp_net.lua` 的 `CLASS.ReturnBat` 分支。

## 8. 充电入仓流程 `bat_charge`

```mermaid
flowchart TD
    A[ChargeBating] --> B[读取 Chbat_Info]
    B --> C{重启恢复?}
    C -->|是| D[询问仓控板并恢复 ch_state]
    C -->|否| E[等待初始仓状态]
    D --> F
    E --> F{ch_state=-1: 所有仓关闭?}
    F -->|否| F1[超时上报1]
    F -->|是| G{回收仓已有电池?}
    G -->|是| G1[上报0x0B并结束]
    G -->|否| H[停止该仓充电<br/>ch_state=0]
    H --> I[打开回收仓]
    I --> J{门打开?}
    J -->|否且未超时| I
    J -->|否且超时| J1[上报2]
    J -->|是| K[ch_state=1<br/>等待关门]
    K --> L{门关闭?}
    L -->|否且未超时| K
    L -->|否且超时| L1[上报3]
    L -->|是| M[ch_state=2<br/>等待电池识别]
    M --> N{检测到 BT/电压?}
    N -->|否| N1[再次开门或超时上报4/0x0A]
    N -->|是| O[识别电池参数并下发首次充电]
    O --> P[ch_state=3<br/>核对实际BT与订单BT]
    P -->|匹配| Q[上报1A/1B<br/>设置 Bat_Fcha_Flag<br/>转自动充电]
    P -->|不匹配| R[上报5<br/>锁门、清理 BT/仓信息]
    Q --> S[清理 Chbat_State/临时订单字段]
    R --> S
```

**源码：** `user/user.lua:bat_charge`；订单入口为 `user/tcp_net.lua:CLASS.ChargeBat`。

## 9. 取电流程 `bat_quout`

```mermaid
flowchart TD
    A[QuBating] --> B[读取 Qubat_Info]
    B --> C{重启恢复?}
    C -->|是| D[询问释放仓<br/>停止充电并等待稳定]
    C -->|否| E[等待仓门关闭、485有效]
    D --> F{仓门已开或电池已不在?}
    E --> F
    F -->|是| G[上报1A<br/>关闭充电、清理仓信息]
    F -->|否| H[qu_state=-1 -> locking(order_give)]
    H --> I{门反馈打开?}
    I -->|是| G
    I -->|否且未超时| H
    I -->|否且超时| J[上报8取电失败]
    G --> K[Qubat_State=false]
    J --> K
```

**源码：** `user/user.lua:bat_quout`；订单入口为 `user/tcp_net.lua` 的 `CLASS.QuBat` 分支。

## 10. 自动充电判断与执行

```mermaid
flowchart TD
    A[batinfo_update_poll 每仓循环] --> B{attr.bat_BT_get(i)?}
    B -->|否| C[不进入该仓自动充电逻辑]
    B -->|是| D[读取电池额定电压/容量、温度、SOC、充电器状态]
    D --> E[计算 cur_1: 系统/电池额定电流上限]
    D --> F{有 Bat_Cha_Flag?}
    F -->|否| G[按温度和 SOC 计算 cur_2]
    F -->|0x55| H[采用电池请求 Bat_Cha_Cur/Bat_Cha_Vol]
    F -->|0xAA| I[cur_2=0，限制充电]
    G --> J
    H --> J
    I --> J
    J[取 min(cur_1,cur_2)，得到 Chg_Cur/Chg_Vol] --> K{禁充条件?}
    K -->|是| K1[Forb_Chg=true<br/>停止计数]
    K -->|否| L{换电/退电/充电入仓/取电/升级进行中?}
    L -->|是| L1[不自动启动]
    L -->|否| M{仓门关闭且允许充电?}
    M -->|否| N[清零充电计数]
    M -->|是| O{未充满、无充电或电流异常?}
    O -->|是| P[chg_cnt累计]
    O -->|否| Q[计数清零]
    P --> R{计数超过阈值?}
    R -->|1400| R1[短暂停止/等待]
    R -->|1600| R2[can_bus.charging(true,目标电压,目标电流)]
    R2 --> S[充电器通过 CAN 回报电流/状态]
    S --> T{异常、满电、高温、MOS/AFE/压差?}
    T -->|是| U[can_bus.charging(false,0,0)<br/>上报异常]
    T -->|否| V[继续充电并更新状态]
```

自动充电的最终执行点只有 `can_bus.charging`；电池的 `0x55/0xAA` 充电机制回包在 `can_bus.lua` 中更新限制参数，直接调用充电的代码目前是注释状态。

## 11. CAN 控制和反馈闭环

```mermaid
sequenceDiagram
    participant B as 业务状态机/user.lua
    participant C as can_bus.lua
    participant Q as CAN发送队列
    participant X as 仓控板/充电器
    participant A as attr运行时缓存
    participant U as TCP/BLE上报

    B->>C: locking(order, open/close)
    C->>Q: 加入仓门 CAN 指令
    Q->>X: 发送开门/关门
    X-->>C: 门锁状态回包
    C->>A: 更新 Box_Lock、Box_Status_Seq
    C->>U: UP_IND BoxInfo / BLE快照变化
    B->>C: charging(order, flag, voltage, current)
    C->>Q: 加入充电控制 CAN 指令
    Q->>X: 开始/停止充电
    X-->>C: 充电器电流、状态回包
    C->>A: 更新 Bat_Cur、Chg_State
    C-->>B: 业务判断继续/停止/异常
    B->>C: reqbox(order, 1/0)
    C->>Q: 请求仓控状态、485 BT、模拟量
    X-->>C: 多帧状态和 BT 回包
    C->>A: 更新 Bat_Is485、Bat_BT_485、Bat_Vol、Bat_Power
    A->>U: TCP BatInfo / BLE slot_status + battery_status
```

**CAN 控制入口：** `user/can_bus.lua:can_bus.charging`、`locking`、`reqbox`。

## 12. 结果上报和清理

```mermaid
flowchart TD
    A[业务状态机得到结果码] --> B[sys.publish UP_IND / UP_IND_S]
    B --> C{TCP-N/TCP-S}
    C --> C1[组装二进制结果帧]
    C1 --> C2[等待服务器 ACK]
    C2 -->|成功| C3{成功结果且订单号匹配?}
    C3 -->|是| C4[清理 Exbat_Info 等持久订单]
    C3 -->|否| C5[保留订单/结果等待重试]
    C2 -->|失败/超时| C5

    B --> D{BLE 订单?}
    D -->|是| E[UP_IND 被 ble_server 订阅]
    E --> F[orders.update 持久化 completed/failed 和实际BT]
    F --> G{持久化成功?}
    G -->|否| G1[不发送伪造终态，打印失败]
    G -->|是| H[发送签名 swap_result]
    H --> I{手机 ACK?}
    I -->|是| J[orders.confirm 标记 result_acked]
    I -->|否| K[关键消息重发/重连后 swap_query]
```

协议语义上，`ack=0` 只表示受理或收到，不表示换电完成；只有实际状态机完成并持久化终态后，才发送换电结果。

## 13. 代码导航

| 模块 | 主要职责 | 关键入口 |
| --- | --- | --- |
| `main.lua` | 固件启动、加载模块、启动 `sys.run` | `require "user"`, `require "ble_server"` |
| `user/user.lua` | 业务状态机、自动充电、异常监控、恢复 | `user_init`, `user_poll`, `bat_exchange`, `bat_return`, `bat_charge`, `bat_quout` |
| `user/attr.lua` | 运行时缓存和传统 TCP 订单持久化 | `attr.*_info_set`, `attr.bat_clean` |
| `user/can_bus.lua` | CAN 收发、仓门、充电、仓控板询问 | `charging`, `locking`, `reqbox`, `rece_process` |
| `user/tcp_net.lua` | TCP-N 二进制协议、订单接收、结果上传 | `class_process`, `upload_indicate`, `poll_task` |
| `user/tcp_s.lua` | TCP-S/备用链路二进制协议 | `class_process`, `upload_indicate`, `poll_task` |
| `user/ble_server.lua` | BLE JSON 分帧、握手、快照、订单入口和结果 | `receive_data`, `handle_message`, `snapshot`, `handle_swap` |
| `user/ble_swap_orders.lua` | BLE 订单去重、持久化、实时仓况复核 | `admit`, `update`, `confirm`, `refresh_return`, `refresh_release` |

