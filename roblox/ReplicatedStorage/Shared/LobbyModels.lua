-- LobbyModels.lua
-- Junk Town's buildings and props that are free Creator Store models
-- (picked with tools/model_search.py: free, no scripts, verified creator;
-- approved by the user 2026-11-17, "the lobby is all rectangles").
-- `python3 tools/studio/store_models.py --set lobby` reads them in Studio
-- into Modules/LobbyModelData; StoreModelBake puts them into the place
-- (ServerStorage.LobbyModels) and Maps/LobbyHub places them, falling back
-- to its own part-built look where a model is missing.
-- id = Creator Store asset id, by = its creator (credit).

return {
	house_mushroom = { id = 88321721301306,  by = "Unbravemec" },
	house_big      = { id = 14849205011,     by = "TANORV" },
	house_small    = { id = 16516958059,     by = "Starblaze Games" },
	house_garden   = { id = 114113800334949, by = "andrzejf48" },
	shop_awning    = { id = 8372522289,      by = "Koreann_Banana" },
	tree_round     = { id = 10307696329,     by = "Roblox Building Team Offical" },
	tree_puff      = { id = 9281027181,      by = "piperstrong1114" },
	tree_tall      = { id = 13870570014,     by = "lukabricks" },
	lamp_plain     = { id = 14212653287,     by = "9bsts" },
	lamp_fancy     = { id = 9069593102,      by = "Mehdiw8" },
	fence          = { id = 8399365124,      by = "A_RandomPuppy" },
	gate           = { id = 73623485991699,  by = "ninyo0403" },
	bench          = { id = 4141588213,      by = "bearduckmonkey" },
	fountain       = { id = 10288583819,     by = "FunGameStudioz" },
	stall          = { id = 86311252190175,  by = "IAmASwedishMale" },
	junk_pile      = { id = 10627968934,     by = "hobykidstv1" },
	scrap_car      = { id = 13639314270,     by = "DeoderantHuntersSon" },
	pot_flowers    = { id = 8975295794,      by = "Noobbreaking" },
	pot_round      = { id = 4640598453,      by = "AndFroI" },
	barrel_metal   = { id = 14452389275,     by = "JSCHRISP" },
	barrel_rusty   = { id = 13304723548,     by = "2BeeSupreme" },
	crate          = { id = 8419520099,      by = "TicTacimabigmac" },
	crates         = { id = 137577456185908, by = "moarterstudios" },
}
