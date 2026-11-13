-- StoreModels.lua
-- Items whose model is a free Creator Store model (picked with
-- tools/model_search.py: free, no scripts, verified creator; approved by the
-- user 2026-11-12; models built from unions or whose mesh will not load
-- at run time were swapped for ones that do, also approved). tools/studio/store_models.py reads each one in Studio
-- into Modules/StoreModelData, which ItemModelPreloader builds from.
-- id = Creator Store asset id, by = its creator (credit).

return {
	["Washing Machine"]   = { id = 7335792229,      by = "Socialize_d" },
	["Old TV"]            = { id = 10759263387,     by = "pontoreziik" },
	["Traffic Cone"]      = { id = 8952512774,      by = "TheDiamondjordan" },
	["Toaster"]           = { id = 14205276842,     by = "Tona1186" },
	["Piano"]             = { id = 129520537903079, by = "Newdial" },
	["Bicycle"]           = { id = 91358100215341,  by = "Wish Game" },
	["Electric Guitar"]   = { id = 128574882233728, by = "GP \u{AD50}\u{B3C4}\u{C18C}" },
	["Refrigerator"]      = { id = 5350328355,      by = "TrustedRat" },
	["Wheelbarrow"]       = { id = 8823211368,      by = "daon2000" },
	["Trash Can"]         = { id = 11508587471,     by = "RTopix" },
	["Watermelon"]        = { id = 8729248863,      by = "LDI_P" },
	["Mattress"]          = { id = 104632916712323, by = "Innovation Safety Inspection Agency" },
	["Fire Extinguisher"] = { id = 16017795520,     by = "DEV_MohamedTarek" },
	["Bowling Ball"]      = { id = 12866254254,     by = "Hyperborea Games" },
	["Teddy Bear"]        = { id = 4919878545,      by = "The_Deceiver" },
	["Office Chair"]      = { id = 131726966724793, by = "danimani019" },
	["Lawn Mower"]        = { id = 9157731797,      by = "dothedes123400" },
	["Toilet"]            = { id = 15153656984,     by = "Notsgavrilis" },
	["Rocking Horse"]     = { id = 5674846912,      by = "Jinji945" },
	["Hot Dog"]           = { id = 6141275475,      by = "LightningGoId" },
	["Boombox"]           = { id = 1439051230,      by = "Pepmynt" },
	["Old Tire"]          = { id = 8130199601,      by = "Trickshotblaster" },
}
