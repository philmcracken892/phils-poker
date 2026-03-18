Config = {}

Config.MinPlayers = 2
Config.MaxPlayers = 6
Config.BuyInMin = 10
Config.BuyInMax = 1000
Config.SmallBlind = 5
Config.BigBlind = 10

-- Poker table models (add more if needed)
Config.PokerModels = {
    `p_tablepoker01x`,
    `p_tablepoker02x`,
    `p_tablepoker03x`,
    `p_amb_poker_table01x`,
}

Config.AI = {
    Enabled = true,
    MaxBots = 5,
    TurnDelay = {2000, 4000},
    StartingChips = {500, 2000},
    Personalities = {
        { name = "Tight Tim", style = "tight", aggression = 0.3, bluffChance = 0.05 },
        { name = "Loose Lucy", style = "loose", aggression = 0.5, bluffChance = 0.25 },
        { name = "Aggressive Al", style = "aggressive", aggression = 0.8, bluffChance = 0.3 },
        { name = "Cautious Carl", style = "passive", aggression = 0.2, bluffChance = 0.1 },
        { name = "Wild Wendy", style = "maniac", aggression = 0.9, bluffChance = 0.4 },
        { name = "Solid Sam", style = "balanced", aggression = 0.5, bluffChance = 0.15 }
    }
}

Config.Debug = true
