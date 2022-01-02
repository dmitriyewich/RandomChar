script_name("RandomChar")
script_author("dmitriyewich")
script_url("https://vk.com/dmitriyewichmods")
script_properties('work-in-pause', 'forced-reloading-only')
script_version("0.2")

local lffi, ffi = pcall(require, 'ffi')
local lmemory, memory = pcall(require, 'memory')

local lencoding, encoding = pcall(require, 'encoding')

encoding.default = 'CP1251'
u8 = encoding.UTF8
CP1251 = encoding.CP1251

local function isarray(t, emptyIsObject)
	if type(t)~='table' then return false end
	if not next(t) then return not emptyIsObject end
	local len = #t
	for k,_ in pairs(t) do
		if type(k)~='number' then
			return false
		else
			local _,frac = math.modf(k)
			if frac~=0 or k<1 or k>len then
				return false
			end
		end
	end
	return true
end

local function map(t,f)
	local r={}
	for i,v in ipairs(t) do r[i]=f(v) end
	return r
end

local keywords = {["and"]=1,["break"]=1,["do"]=1,["else"]=1,["elseif"]=1,["end"]=1,["false"]=1,["for"]=1,["function"]=1,["goto"]=1,["if"]=1,["in"]=1,["local"]=1,["nil"]=1,["not"]=1,["or"]=1,["repeat"]=1,["return"]=1,["then"]=1,["true"]=1,["until"]=1,["while"]=1}

local function neatJSON(value, opts) -- https://github.com/Phrogz/NeatJSON
	opts = opts or {}
	if opts.wrap==nil  then opts.wrap = 80 end
	if opts.wrap==true then opts.wrap = -1 end
	opts.indent         = opts.indent         or "  "
	opts.arrayPadding  = opts.arrayPadding  or opts.padding      or 0
	opts.objectPadding = opts.objectPadding or opts.padding      or 0
	opts.afterComma    = opts.afterComma    or opts.aroundComma  or 0
	opts.beforeComma   = opts.beforeComma   or opts.aroundComma  or 0
	opts.beforeColon   = opts.beforeColon   or opts.aroundColon  or 0
	opts.afterColon    = opts.afterColon    or opts.aroundColon  or 0
	opts.beforeColon1  = opts.beforeColon1  or opts.aroundColon1 or opts.beforeColon or 0
	opts.afterColon1   = opts.afterColon1   or opts.aroundColon1 or opts.afterColon  or 0
	opts.beforeColonN  = opts.beforeColonN  or opts.aroundColonN or opts.beforeColon or 0
	opts.afterColonN   = opts.afterColonN   or opts.aroundColonN or opts.afterColon  or 0

	local colon  = opts.lua and '=' or ':'
	local array  = opts.lua and {'{','}'} or {'[',']'}
	local apad   = string.rep(' ', opts.arrayPadding)
	local opad   = string.rep(' ', opts.objectPadding)
	local comma  = string.rep(' ',opts.beforeComma)..','..string.rep(' ',opts.afterComma)
	local colon1 = string.rep(' ',opts.beforeColon1)..colon..string.rep(' ',opts.afterColon1)
	local colonN = string.rep(' ',opts.beforeColonN)..colon..string.rep(' ',opts.afterColonN)

	local build -- set lower
	local function rawBuild(o,indent)
		if o==nil then
			return indent..'null'
		else
			local kind = type(o)
			if kind=='number' then
				local _,frac = math.modf(o)
				return indent .. string.format( frac~=0 and opts.decimals and ('%.'..opts.decimals..'f') or '%g', o)
			elseif kind=='boolean' or kind=='nil' then
				return indent..tostring(o)
			elseif kind=='string' then
				return indent..string.format('%q', o):gsub('\\\n','\\n')
			elseif isarray(o, opts.emptyTablesAreObjects) then
				if #o==0 then return indent..array[1]..array[2] end
				local pieces = map(o, function(v) return build(v,'') end)
				local oneLine = indent..array[1]..apad..table.concat(pieces,comma)..apad..array[2]
				if opts.wrap==false or #oneLine<=opts.wrap then return oneLine end
				if opts.short then
					local indent2 = indent..' '..apad;
					pieces = map(o, function(v) return build(v,indent2) end)
					pieces[1] = pieces[1]:gsub(indent2,indent..array[1]..apad, 1)
					pieces[#pieces] = pieces[#pieces]..apad..array[2]
					return table.concat(pieces, ',\n')
				else
					local indent2 = indent..opts.indent
					return indent..array[1]..'\n'..table.concat(map(o, function(v) return build(v,indent2) end), ',\n')..'\n'..(opts.indentLast and indent2 or indent)..array[2]
				end
			elseif kind=='table' then
				if not next(o) then return indent..'{}' end

				local sortedKV = {}
				local sort = opts.sort or opts.sorted
				for k,v in pairs(o) do
					local kind = type(k)
					if kind=='string' or kind=='number' then
						sortedKV[#sortedKV+1] = {k,v}
						if sort==true then
							sortedKV[#sortedKV][3] = tostring(k)
						elseif type(sort)=='function' then
							sortedKV[#sortedKV][3] = sort(k,v,o)
						end
					end
				end
				if sort then table.sort(sortedKV, function(a,b) return a[3]<b[3] end) end
				local keyvals
				if opts.lua then
					keyvals=map(sortedKV, function(kv)
						if type(kv[1])=='string' and not keywords[kv[1]] and string.match(kv[1],'^[%a_][%w_]*$') then
							return string.format('%s%s%s',kv[1],colon1,build(kv[2],''))
						else
							return string.format('[%q]%s%s',kv[1],colon1,build(kv[2],''))
						end
					end)
				else
					keyvals=map(sortedKV, function(kv) return string.format('%q%s%s',kv[1],colon1,build(kv[2],'')) end)
				end
				keyvals=table.concat(keyvals, comma)
				local oneLine = indent.."{"..opad..keyvals..opad.."}"
				if opts.wrap==false or #oneLine<opts.wrap then return oneLine end
				if opts.short then
					keyvals = map(sortedKV, function(kv) return {indent..' '..opad..string.format('%q',kv[1]), kv[2]} end)
					keyvals[1][1] = keyvals[1][1]:gsub(indent..' ', indent..'{', 1)
					if opts.aligned then
						local longest = math.max(table.unpack(map(keyvals, function(kv) return #kv[1] end)))
						local padrt   = '%-'..longest..'s'
						for _,kv in ipairs(keyvals) do kv[1] = padrt:format(kv[1]) end
					end
					for i,kv in ipairs(keyvals) do
						local k,v = kv[1], kv[2]
						local indent2 = string.rep(' ',#(k..colonN))
						local oneLine = k..colonN..build(v,'')
						if opts.wrap==false or #oneLine<=opts.wrap or not v or type(v)~='table' then
							keyvals[i] = oneLine
						else
							keyvals[i] = k..colonN..build(v,indent2):gsub('^%s+','',1)
						end
					end
					return table.concat(keyvals, ',\n')..opad..'}'
				else
					local keyvals
					if opts.lua then
						keyvals=map(sortedKV, function(kv)
							if type(kv[1])=='string' and not keywords[kv[1]] and string.match(kv[1],'^[%a_][%w_]*$') then
								return {table.concat{indent,opts.indent,kv[1]}, kv[2]}
							else
								return {string.format('%s%s[%q]',indent,opts.indent,kv[1]), kv[2]}
							end
						end)
					else
						keyvals = {}
						for i,kv in ipairs(sortedKV) do
							keyvals[i] = {indent..opts.indent..string.format('%q',kv[1]), kv[2]}
						end
					end
					if opts.aligned then
						local longest = math.max(table.unpack(map(keyvals, function(kv) return #kv[1] end)))
						local padrt   = '%-'..longest..'s'
						for _,kv in ipairs(keyvals) do kv[1] = padrt:format(kv[1]) end
					end
					local indent2 = indent..opts.indent
					for i,kv in ipairs(keyvals) do
						local k,v = kv[1], kv[2]
						local oneLine = k..colonN..build(v,'')
						if opts.wrap==false or #oneLine<=opts.wrap or not v or type(v)~='table' then
							keyvals[i] = oneLine
						else
							keyvals[i] = k..colonN..build(v,indent2):gsub('^%s+','',1)
						end
					end
					return indent..'{\n'..table.concat(keyvals, ',\n')..'\n'..(opts.indentLast and indent2 or indent)..'}'
				end
			end
		end
	end

	-- indexed by object, then by indent level
	local function memoize()
		local memo = setmetatable({},{_mode='k'})
		return function(o,indent)
			if o==nil then
				return indent..(opts.lua and 'nil' or 'null')
			elseif o~=o then --test for NaN
				return indent..(opts.lua and '0/0' or '"NaN"')
			elseif o==math.huge then
				return indent..(opts.lua and '1/0' or '9e9999')
			elseif o==-math.huge then
				return indent..(opts.lua and '-1/0' or '-9e9999')
			end
			local byIndent = memo[o]
			if not byIndent then
				byIndent = setmetatable({},{_mode='k'})
				memo[o] = byIndent
			end
			if not byIndent[indent] then
				byIndent[indent] = rawBuild(o,indent)
			end
			return byIndent[indent]
		end
	end

	build = memoize()
	return build(value,'')
end

function savejson(table, path)
    local f = io.open(path, "w")
    f:write(table)
    f:close()
end

function convertTableToJsonString(config)
	return (neatJSON(config, { wrap = 174, sort = true, aligned = true, arrayPadding = 1, afterComma = 1 }))
end

local config = {}

if doesFileExist("moonloader/config/RandomChar.json") then
    local f = io.open("moonloader/config/RandomChar.json")
    config = decodeJson(f:read("*a"))
    f:close()
else
	config = {["chars"] = {}}

	if not doesDirectoryExist('moonloader/config') then createDirectory('moonloader/config') end

    savejson(convertTableToJsonString(config), "moonloader/config/RandomChar.json")
end

math.randomseed( os.clock()^5 )
math.random() math.random() math.random()

function random(min, max)
	rand = math.random(min, max)
    return tonumber(rand)
end


local testNameModel = {
	[0] = "cj", [1] = "truth", [2] = "maccer", [3] = "andre", [4] = "bbthin", [5] = "bb", [6] = "emmet", [7] = "male01", [8] = "janitor", [9] = "bfori",
	[10] = "bfost", [11] = "vbfycrp", [12] = "bfyri", [13] = "bfyst", [14] = "bmori", [15] = "bmost", [16] = "bmyap", [17] = "bmybu", [18] = "bmybe",
	[19] = "bmydj", [20] = "bmyri", [21] = "bmycr", [22] = "bmyst", [23] = "wmybmx", [24] = "wbdyg1", [25] = "wbdyg2", [26] = "wmybp", [27] = "wmycon",
	[28] = "bmydrug", [29] = "wmydrug", [30] = "hmydrug", [31] = "dwfolc", [32] = "dwmolc1", [33] = "dwmolc2", [34] = "dwmylc1", [35] = "hmogar", [36] = "wmygol1",
	[37] = "wmygol2", [38] = "hfori", [39] = "hfost", [40] = "hfyri", [41] = "hfyst", [42] = "jethro", [43] = "hmori", [44] = "hmost", [45] = "hmybe", [46] = "hmyri",
	[47] = "hmycr", [48] = "hmyst", [49] = "omokung", [50] = "wmymech", [51] = "bmymoun", [52] = "wmymoun", [53] = "ofori", [54] = "ofost", [55] = "ofyri", [56] = "ofyst",
	[57] = "omori", [58] = "omost", [59] = "omyri", [60] = "omyst", [61] = "wmyplt", [62] = "wmopj", [63] = "bfypro", [64] = "hfypro", [65] = "kendl", [66] = "bmypol1",
	[67] = "bmypol2", [68] = "wmoprea", [69] = "sbfyst", [70] = "wmosci", [71] = "wmysgrd", [72] = "swmyhp1", [73] = "swmyhp2", [74] = "-", [75] = "swfopro", [76] = "wfystew",
	[77] = "swmotr1", [78] = "wmotr1", [79] = "bmotr1", [80] = "vbmybox", [81] = "vwmybox", [82] = "vhmyelv", [83] = "vbmyelv", [84] = "vimyelv", [85] = "vwfypro",
	[86] = "ryder3", [87] = "vwfyst1", [88] = "wfori", [89] = "wfost", [90] = "wfyjg", [91] = "wfyri", [92] = "wfyro", [93] = "wfyst", [94] = "wmori", [95] = "wmost",
	[96] = "wmyjg", [97] = "wmylg", [98] = "wmyri", [99] = "wmyro", [100] = "wmycr", [101] = "wmyst", [102] = "ballas1", [103] = "ballas2", [104] = "ballas3", [105] = "fam1",
	[106] = "fam2", [107] = "fam3", [108] = "lsv1", [109] = "lsv2", [110] = "lsv3", [111] = "maffa", [112] = "maffb", [113] = "mafboss", [114] = "vla1", [115] = "vla2",
	[116] = "vla3", [117] = "triada", [118] = "triadb", [119] = "sindaco", [120] = "triboss", [121] = "dnb1", [122] = "dnb2", [123] = "dnb3", [124] = "vmaff1",
	[125] = "vmaff2", [126] = "vmaff3", [127] = "vmaff4", [128] = "dnmylc", [129] = "dnfolc1", [130] = "dnfolc2", [131] = "dnfylc", [132] = "dnmolc1", [133] = "dnmolc2",
	[134] = "sbmotr2", [135] = "swmotr2", [136] = "sbmytr3", [137] = "swmotr3", [138] = "wfybe", [139] = "bfybe", [140] = "hfybe", [141] = "sofybu", [142] = "sbmyst", [143] = "sbmycr",
	[144] = "bmycg", [145] = "wfycrk", [146] = "hmycm", [147] = "wmybu", [148] = "bfybu", [149] = "smokev", [150] = "wfybu", [151] = "dwfylc1", [152] = "wfypro", [153] = "wmyconb",
	[154] = "wmybe", [155] = "wmypizz", [156] = "bmobar", [157] = "cwfyhb", [158] = "cwmofr", [159] = "cwmohb1", [160] = "cwmohb2", [161] = "cwmyfr", [162] = "cwmyhb1",
	[163] = "bmyboun", [164] = "wmyboun", [165] = "wmomib", [166] = "bmymib", [167] = "wmybell", [168] = "bmochil", [169] = "sofyri", [170] = "somyst", [171] = "vwmybjd",
	[172] = "vwfycrp", [173] = "sfr1", [174] = "sfr2", [175] = "sfr3", [176] = "bmybar", [177] = "wmybar", [178] = "wfysex", [179] = "wmyammo", [180] = "bmytatt",
	[181] = "vwmycr", [182] = "vbmocd", [183] = "vbmycr", [184] = "vhmycr", [185] = "sbmyri", [186] = "somyri", [187] = "somybu", [188] = "swmyst", [189] = "wmyva",
	[190] = "copgrl3", [191] = "gungrl3", [192] = "mecgrl3", [193] = "nurgrl3", [194] = "crogrl3", [195] = "gangrl3", [196] = "cwfofr", [197] = "cwfohb",
	[198] = "cwfyfr1", [199] = "cwfyfr2", [200] = "cwmyhb2", [201] = "dwfylc2", [202] = "dwmylc2", [203] = "omykara", [204] = "wmykara", [205] = "wfyburg",
	[206] = "vwmycd", [207] = "vhfypro", [208] = "suzie", [209] = "omonood", [210] = "omoboat", [211] = "wfyclot", [212] = "vwmotr1", [213] = "vwmotr2",
	[214] = "vwfywai", [215] = "sbfori", [216] = "swfyri", [217] = "wmyclot", [218] = "sbfost", [219] = "sbfyri", [220] = "sbmocd", [221] = "sbmori",
	[222] = "sbmost", [223] = "shmycr", [224] = "sofori", [225] = "sofost", [226] = "sofyst", [227] = "somobu", [228] = "somori", [229] = "somost",
	[230] = "swmotr5", [231] = "swfori", [232] = "swfost", [233] = "swfyst", [234] = "swmocd", [235] = "swmori", [236] = "swmost", [237] = "shfypro",
	[238] = "sbfypro", [239] = "swmotr4", [240] = "swmyri", [241] = "smyst", [242] = "smyst2", [243] = "sfypro", [244] = "vbfyst2", [245] = "vbfypro",
	[246] = "vhfyst3", [247] = "bikera", [248] = "bikerb", [249] = "bmypimp", [250] = "swmycr", [251] = "wfylg", [252] = "wmyva2", [253] = "bmosec",
	[254] = "bikdrug", [255] = "wmych", [256] = "sbfystr", [257] = "swfystr", [258] = "heck1", [259] = "heck2", [260] = "bmycon", [261] = "wmycd1",
	[262] = "bmocd", [263] = "vwfywa2", [264] = "wmoice", [265] = "tenpen", [266] = "pulaski", [267] = "hern", [268] = "dwayne", [269] = "smoke", [270] = "sweet",
	[271] = "ryder", [272] = "forelli", [273] = "tbone", [274] = "laemt1", [275] = "lvemt1", [276] = "sfemt1", [277] = "lafd1", [278] = "lvfd1", [279] = "sffd1",
	[280] = "lapd1", [281] = "sfpd1", [282] = "lvpd1", [283] = "csher", [284] = "lapdm1", [285] = "swat", [286] = "fbi", [287] = "army", [288] = "dsher", [289] = "zero",
	[290] = "rose", [291] = "paul", [292] = "cesar", [293] = "ogloc", [294] = "wuzimu", [295] = "torino", [296] = "jizzy", [297] = "maddogg", [298] = "cat",
	[299] = "claude", [300] = "lapdna", [301] = "sfpdna", [302] = "lvpdna", [303] = "lapdpc", [304] = "lapdpd", [305] = "lvpdpc", [306] = "wfyclpd", [307] = "vbfycpd",
	[308] = "wfyclem", [309] = "wfycllv", [310] = "csherna", [311] = "dsherna";}


local text_text = [[peds
1, TRUTH, TRUTH, CIVMALE, STAT_STD_MISSION, man, 1FFF, 0, null, 9,9, PED_TYPE_SPC,VOICE_GNG_TRUTH ,VOICE_GNG_TRUTH
2, MACCER, MACCER, CIVMALE, STAT_STD_MISSION, man, 1FFF, 0, null, 9,9, PED_TYPE_SPC, VOICE_GNG_MACCER , VOICE_GNG_MACCER
3, ANDRE, ANDRE, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GEN, VOICE_GEN_MALE01, VOICE_GEN_MALE01 #Andre
4, BBTHIN, BBTHIN, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GANG, VOICE_GNG_BIG_BEAR, VOICE_GNG_BIG_BEAR #Big Bear
5, BB, BB, CIVMALE, STAT_SENSIBLE_GUY, fatman, 0, 0, fatman, 1,4, PED_TYPE_GANG, VOICE_GNG_BIG_BEAR, VOICE_GNG_BIG_BEAR #Big Bear
6, EMMET, EMMET, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GEN, VOICE_GEN_MALE01, VOICE_GEN_MALE01 #Emmet
8, JANITOR, JANITOR, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GEN, VOICE_GEN_MALE01, VOICE_GEN_MALE01 #Janitor
42, JETHRO, JETHRO, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GEN, VOICE_GEN_MALE01, VOICE_GEN_MALE01 #Jethro
65, KENDL, KENDL, CIVFEMALE, STAT_SENSIBLE_GUY, woman, 0, 0, woman, 1,4, PED_TYPE_GEN, VOICE_GEN_HFYRI, VOICE_GEN_HFYRI #Kendl
86, RYDER3, RYDER3, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GANG, VOICE_GNG_RYDER, VOICE_GNG_RYDER #Ryder
119, SINDACO, SINDACO, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GEN, VOICE_GEN_MALE01, VOICE_GEN_MALE01 #Sindacco
149, SMOKEV, SMOKEV, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GANG, VOICE_GNG_SMOKE, VOICE_GNG_SMOKE #Big Smoke
208, SUZIE, SUZIE, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GANG, VOICE_GNG_STRI1, VOICE_GNG_STRI1 #Su Xi Mu (Suzie)
273, TBONE, TBONE, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GANG, VOICE_GNG_TBONE, VOICE_GNG_TBONE #T-Bone Mendez
289, ZERO, ZERO, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GEN, VOICE_GEN_MALE01, VOICE_GEN_MALE01 #Zero
7, male01, male01, CIVMALE, STAT_SENSIBLE_GUY, man, 0, 0, man, 1,4, PED_TYPE_GEN, VOICE_GEN_MALE01, VOICE_GEN_MALE01
9, BFORI, BFORI, CIVFEMALE, STAT_COWARD, woman, 120C,0, man,7,3,PED_TYPE_GEN,VOICE_GEN_BFORI,VOICE_GEN_BFORI
10, BFOST, BFOST, CIVFEMALE, STAT_STREET_GIRL, oldfatwoman,1003,0, null,9,3,PED_TYPE_GEN, VOICE_GEN_BFOST, VOICE_GEN_BFOST
11, VBFYCRP, VBFYCRP, CIVFEMALE, STAT_SUIT_GIRL, woman, 130C,0, null,3,7,PED_TYPE_GEN,VOICE_GEN_BFYCRP ,VOICE_GEN_BFYCRP
12, BFYRI, BFYRI, CIVFEMALE, STAT_COWARD, sexywoman, 120C,1, null,7,9,PED_TYPE_GEN,VOICE_GEN_BFYRI ,VOICE_GEN_BFYRI
13, BFYST, BFYST, CIVFEMALE,  STAT_STREET_GIRL, woman,1983,1, null,0,3,PED_TYPE_GEN,VOICE_GEN_BFYST ,VOICE_GEN_BFYST
14, BMORI, bmori, CIVMALE, STAT_COWARD, man, 120C,0, man,9,8,PED_TYPE_GEN,VOICE_GEN_BMORI,VOICE_GEN_BMORI
15, BMOST, bmost, CIVMALE, STAT_STREET_GUY, man,1003,0, man,8,9,PED_TYPE_GEN,VOICE_GEN_BMOST ,VOICE_GEN_BMOST
16, BMYAP, BMYAP, CIVMALE, STAT_COWARD, man, 110F,0, null,0,8,PED_TYPE_GEN,VOICE_GEN_BMYAP ,VOICE_GEN_BMYAP
17, BMYBU, BMYBU, CIVMALE, STAT_SUIT_GUY, man, 120C,1, man,7,9,PED_TYPE_GEN,VOICE_GEN_BMYBU ,VOICE_GEN_BMYBU
18, BMYBE, BMYBE, CIVMALE, STAT_BEACH_GUY, man,1000,0, beach,7,3,PED_TYPE_GEN,VOICE_GEN_BMYBE ,VOICE_GEN_BMYBE
19, BMYDJ, BMYDJ, CIVMALE, STAT_STREET_GUY, gang1, 170F,1, null,5,0,PED_TYPE_GEN,VOICE_GEN_BMYDJ ,VOICE_GEN_BMYDJ
20, BMYRI, BMYRI, CIVMALE, STAT_COWARD, man, 120C,1, null,7,5,PED_TYPE_GEN,VOICE_GEN_BMYRI ,VOICE_GEN_BMYRI
21, BMYCR, BMYCR, CRIMINAL, STAT_CRIMINAL, gang1, 110F,1, man,5,0,PED_TYPE_GEN,VOICE_GEN_BMYCR ,VOICE_GEN_BMYCR
22, BMYST, BMYST, CIVMALE, STAT_STREET_GUY, gang2,1983,1, null,0,3,PED_TYPE_GEN,VOICE_GEN_BMYST ,VOICE_GEN_BMYST
23, WMYBMX, WMYBMX, CIVMALE, STAT_STREET_GUY, man,0800,0, null,6,4,PED_TYPE_GEN,VOICE_GEN_WMYBMX ,VOICE_GEN_WMYBMX
24, WBDYG1, WBDYG1, CIVMALE, STAT_TOUGH_GUY, man, 170F,1, man,10,1,PED_TYPE_GEN,VOICE_GEN_BBDYG1 ,VOICE_GEN_BBDYG1
25, WBDYG2, WBDYG2, CIVMALE, STAT_TOUGH_GUY, man, 170F,1, man,2,1,PED_TYPE_GEN,VOICE_GEN_BBDYG2 ,VOICE_GEN_BBDYG2
26, WMYBP, WMYBP, CIVMALE, STAT_GEEK_GUY, man,1000,1, man,2,6,PED_TYPE_GEN,VOICE_GEN_WMYBP ,VOICE_GEN_WMYBP
27, WMYCON, WMYCON, CIVMALE, STAT_SUIT_GUY, man, 130C,1, man,1,2,PED_TYPE_GEN,VOICE_GEN_WMYCON ,VOICE_GEN_WMYCON
28, BMYDRUG, BMYdrug, CRIMINAL, STAT_CRIMINAL, gang2, 110F,0, man,5,5,PED_TYPE_GEN,VOICE_GEN_BMYDRUG ,VOICE_GEN_BMYDRUG
29, WMYDRUG, WMYdrug, CRIMINAL, STAT_CRIMINAL, man, 110F,0, man,4,4,PED_TYPE_GEN,VOICE_GEN_WMYDRUG ,VOICE_GEN_WMYDRUG
30, HMYDRUG, HMYdrug, CRIMINAL, STAT_CRIMINAL, man, 110F,0, man,9,7,PED_TYPE_GEN,VOICE_GEN_HMYDRUG ,VOICE_GEN_HMYDRUG
31, DWFOLC, dwfolc, CIVFEMALE, STAT_OLD_GIRL, oldfatwoman,1003,0, null,1,10,PED_TYPE_GEN,VOICE_GEN_DWFOLC,VOICE_GEN_DWFOLC
32, DWMOLC1, dwmolc1, CIVMALE, STAT_OLD_GUY, man,1003,0, null,1,10,PED_TYPE_GEN,VOICE_GEN_DWMOLC1,VOICE_GEN_DWMOLC1
33, DWMOLC2, dwmolc2, CIVMALE, STAT_OLD_GUY, man,1003,0, null,1,2,PED_TYPE_GEN,VOICE_GEN_DWMOLC2,VOICE_GEN_DWMOLC2
34, DWMYLC1, dwmylc1, CIVMALE, STAT_TOUGH_GUY, man,1983,1, null,2,1,PED_TYPE_GEN,VOICE_GEN_DWMYLC1,VOICE_GEN_DWMYLC2
35, HMOGAR, HMOgar, CIVMALE, STAT_OLD_GUY, man, 1003,0, null,10,2,PED_TYPE_GEN,VOICE_GEN_WMYGAR ,VOICE_GEN_WMYGAR
36, WMYGOL1, WMYgol1, CIVMALE, STAT_COWARD, man, 170F,0, null,2,3,PED_TYPE_GEN,VOICE_GEN_WMYGOL1 ,VOICE_GEN_WMYGOL1
37, WMYGOL2, WMYgol2, CIVMALE, STAT_COWARD, man, 170F,0, null,7,3,PED_TYPE_GEN,VOICE_GEN_WMYGOL2 ,VOICE_GEN_WMYGOL2
38, HFORI, hfori, CIVFEMALE, STAT_COWARD, woman, 120C,0, man,10,9,PED_TYPE_GEN,VOICE_GEN_HFORI ,VOICE_GEN_HFORI
39, HFOST, hfost, CIVFEMALE, STAT_OLD_GIRL, oldfatwoman,1003,0, man,9,3,PED_TYPE_GEN,VOICE_GEN_HFOST ,VOICE_GEN_HFOST
40, HFYRI, HFYRI, CIVFEMALE, STAT_COWARD, sexywoman, 120C,1, null,7,3,PED_TYPE_GEN,VOICE_GEN_HFYRI ,VOICE_GEN_HFYRI
41, HFYST, HFYST, CIVFEMALE, STAT_STREET_GIRL, woman,1983,1, null,6,1,PED_TYPE_GEN,VOICE_GEN_HFYST ,VOICE_GEN_HFYST
43, HMORI, HMORI, CIVMALE, STAT_COWARD, man, 120C,0, man,10,9,PED_TYPE_GEN,VOICE_GEN_HMORI ,VOICE_GEN_HMORI
44, HMOST, HMOST, CIVMALE, STAT_STREET_GUY, man,1003,0, man,2,2,PED_TYPE_GEN,VOICE_GEN_HMOST ,VOICE_GEN_HMOST
45, HMYBE, HMYBE, CIVMALE, STAT_BEACH_GUY, man,1000,0, beach,7,3,PED_TYPE_GEN,VOICE_GEN_HMYBE ,VOICE_GEN_HMYBE
46, HMYRI, HMYRI, CIVMALE, STAT_SUIT_GUY, man,1983,1, null,6,4,PED_TYPE_GEN,VOICE_GEN_HMYRI ,VOICE_GEN_HMYRI
47, HMYCR, HMYCR, CRIMINAL, STAT_CRIMINAL, man, 110F,1, man,0,0,PED_TYPE_GEN,VOICE_GEN_HMYCR ,VOICE_GEN_HMYCR
48, HMYST, HMYST, CIVMALE, STAT_TOURIST, man, 1983,1, man,0,5,PED_TYPE_GEN,VOICE_GEN_HMYST ,VOICE_GEN_HMYST
49, OMOKUNG, OMOkung, CIVMALE, STAT_OLD_GUY, oldman,1003,0, man,1,4,PED_TYPE_GEN,VOICE_GEN_OMOKUNG ,VOICE_GEN_OMOKUNG
50, WMYMECH, WMYMECH, CIVMALE, STAT_TOUGH_GUY, man,1433,1, null,6,6,PED_TYPE_GEN,VOICE_GEN_WMYMECH ,VOICE_GEN_WMYMECH
51, BMYMOUN, BMYMOUN, CIVMALE, STAT_SENSIBLE_GUY, man,0800,1, man,2,0 PED_TYPE_GEN,VOICE_GEN_BMYMOUN ,VOICE_GEN_BMYMOUN
52, WMYMOUN, WMYMOUN, CIVMALE, STAT_SENSIBLE_GUY, man,0800,1, man,6,2,PED_TYPE_GEN,VOICE_GEN_WMYMOUN ,VOICE_GEN_WMYMOUN
53, OFORI, OFORI, CIVFEMALE, STAT_OLD_GIRL, oldwoman, 120C,0, man,10,1,PED_TYPE_GEN,VOICE_GEN_OFORI,VOICE_GEN_OFORI
54, OFOST, OFOST, CIVFEMALE, STAT_STREET_GIRL, oldwoman,1003,0, null,10,3,PED_TYPE_GEN,VOICE_GEN_OFOST,VOICE_GEN_OFOST
55, OFYRI, OFYRI, CIVFEMALE, STAT_COWARD, woman, 120C,1, null,2,7,PED_TYPE_GEN,VOICE_GEN_OFYRI,VOICE_GEN_OFYRI
56, OFYST, OFYST, CIVFEMALE, STAT_TOURIST, woman,1003,1, null,6,6,PED_TYPE_GEN,VOICE_GEN_OFYST,VOICE_GEN_OFYST
57, OMORI, OMORI, CIVMALE, STAT_COWARD, man, 120C,0, man,10,10,PED_TYPE_GEN,VOICE_GEN_OMORI,VOICE_GEN_OMORI
58, OMOST, OMOST, CIVMALE, STAT_STREET_GUY, man,1003,0, man,2,1,PED_TYPE_GEN,VOICE_GEN_OMOST,VOICE_GEN_OMOST
59, OMYRI, OMYRI, CIVMALE, STAT_COWARD, man, 120C,1, null,2,4,PED_TYPE_GEN,VOICE_GEN_OMYRI ,VOICE_GEN_OMYRI
60, OMYST, OMYST, CIVMALE, STAT_TOURIST, man,1983,1, null,3,6,PED_TYPE_GEN,VOICE_GEN_OMYST ,VOICE_GEN_OMYST
61, WMYPLT, WMYPLT, CIVMALE, STAT_SUIT_GUY, man,1000,1, null,1,2,PED_TYPE_GEN,VOICE_GEN_WMYPLT ,VOICE_GEN_WMYPLT
62, WMOPJ, WMOpj, CIVMALE, STAT_OLD_GUY, oldman,1000,0, null,1,1,PED_TYPE_GEN,VOICE_GEN_WMOPJ ,VOICE_GEN_WMOPJ
63, BFYPRO, BFYPRO, PROSTITUTE, STAT_PROSTITUTE, pro,1000,1, man,1,4,PED_TYPE_GEN,VOICE_GEN_BFYPRO,VOICE_GEN_BFYPRO
64, HFYPRO, HFYPRO, PROSTITUTE, STAT_PROSTITUTE, pro,1000,1, man,1,4,PED_TYPE_GEN,VOICE_GEN_HFYPRO ,VOICE_GEN_HFYPRO
66, BMYPOL1, BMYpol1, CIVMALE, STAT_TOUGH_GUY, man, 110F,1, man,0,0,PED_TYPE_GEN,VOICE_GEN_BMYPOL1 ,VOICE_GEN_BMYPOL1
67, BMYPOL2, BMYpol2, CIVMALE, STAT_TOUGH_GUY, man, 110F,1, man,8,8,PED_TYPE_GEN,VOICE_GEN_BMYPOL2 ,VOICE_GEN_BMYPOL2
68, WMOPREA, WMOprea, CIVMALE, STAT_SUIT_GUY, man, 170F,0, man,1,10,PED_TYPE_GEN,VOICE_GEN_WMOPREA ,VOICE_GEN_WMOPREA
69, SBFYST, sbfyst, CIVFEMALE, STAT_TOURIST, woman,1983,1, null,4,6,PED_TYPE_GEN,VOICE_GEN_SBFYST, VOICE_GEN_SBFYST
70, WMOSCI, WMOsci, CIVMALE, STAT_OLD_GUY, man, 120C,0, null,10,10,PED_TYPE_GEN,VOICE_GEN_WMOSCI ,VOICE_GEN_WMOSCI
71, WMYSGRD, WMYSGRD, CIVMALE, STAT_TOUGH_GUY, man, 170F,1, null,2,6,PED_TYPE_GEN,VOICE_GEN_WMYSGRAD ,VOICE_GEN_WMYSGRAD
72, SWMYHP1, SWMYhp1, CIVMALE, STAT_TOUGH_GUY, man,1983,1, man,8,2,PED_TYPE_GEN,VOICE_GEN_SWMYHP1,VOICE_GEN_SWMYHP1
73, SWMYHP2, SWMYhp2, CIVMALE, STAT_COWARD, man,1882,1, man,2,8,PED_TYPE_GEN,VOICE_GEN_SWMYHP2,VOICE_GEN_SWMYHP2
75, SWFOPRO, sWFOpro, PROSTITUTE, STAT_PROSTITUTE, pro,1000,1, null,3,3,PED_TYPE_GEN,VOICE_GEN_SWFOPRO,VOICE_GEN_SWFOPRO
76, WFYSTEW, WFYSTEW, CIVFEMALE, STAT_GEEK_GIRL, sexywoman,1000,1, null,6,4,PED_TYPE_GEN,VOICE_GEN_WFYSTEW ,VOICE_GEN_WFYSTEW
77, SWMOTR1, sWMOtr1, CIVMALE, STAT_TRAMP_MALE, man,1000,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_SWMOTR1,VOICE_GEN_SWMOTR1
78, WMOTR1, WMOTR1, CIVMALE, STAT_TRAMP_MALE, man,1000,0, man,1,4,PED_TYPE_GEN,VOICE_GEN_WMOTR1,VOICE_GEN_WMOTR1
79, BMOTR1, BMOTR1, CIVMALE, STAT_TRAMP_MALE, man,1000,0, man,1,4,PED_TYPE_GEN,VOICE_GEN_BMOTR1,VOICE_GEN_BMOTR1
80, VBMYBOX, VBMYbox, CIVMALE, STAT_TOUGH_GUY, man, 1000,0, man,1,4,PED_TYPE_GEN,VOICE_GEN_BMYBOX ,VOICE_GEN_BMYBOX
81, VWMYBOX, VWMYbox, CIVMALE, STAT_TOUGH_GUY, man, 1000,0, man,1,4,PED_TYPE_GEN,VOICE_GEN_WMYBOX ,VOICE_GEN_WMYBOX
82, VHMYELV, VHMYELV, CIVMALE, STAT_COWARD, man, 170F,1, null,1,2,PED_TYPE_GEN,VOICE_GEN_VHMYELV,VOICE_GEN_VHMYELV
83, VBMYELV, VBMYELV, CIVMALE, STAT_TOUGH_GUY, man, 170F,1, null,2,1,PED_TYPE_GEN,VOICE_GEN_VBMYELV,VOICE_GEN_VBMYELV
84, VIMYELV, VIMYELV, CIVMALE, STAT_COWARD, man, 170F,1, null,1,1,PED_TYPE_GEN,VOICE_GEN_VIMYELV,VOICE_GEN_VIMYELV
85, VWFYPRO, VWFYPRO, PROSTITUTE, STAT_PROSTITUTE, pro,1000,1, man,1,4,PED_TYPE_GEN,VOICE_GEN_VWFYPRO,VOICE_GEN_VWFYPRO
87, VWFYST1, VWFYST1, CIVFEMALE, STAT_STREET_GIRL, sexywoman,1000,1, man,1,4,PED_TYPE_GEN,VOICE_GEN_VWFYST1 ,VOICE_GEN_VWFYST1
88, WFORI, WFORI, CIVFEMALE, STAT_COWARD, oldwoman, 120C,0, man,10,1,PED_TYPE_GEN,VOICE_GEN_WFORI,VOICE_GEN_WFORI
89, WFOST, WFOST, CIVFEMALE, STAT_STREET_GIRL, oldfatwoman,1003,0, man,1,2,PED_TYPE_GEN,VOICE_GEN_WFOST,VOICE_GEN_WFOST
90, WFYJG, WFYJG, CIVFEMALE, STAT_COWARD, jogwoman,1000,0, beach,9,9,PED_TYPE_GEN,VOICE_GEN_WFYJG ,VOICE_GEN_WFYJG
91, WFYRI, WFYRI, CIVFEMALE, STAT_COWARD, sexywoman, 120C,1, null,4,6,PED_TYPE_GEN,VOICE_GEN_WFYRI ,VOICE_GEN_WFYRI
92, WFYRO, WFYRO, CIVFEMALE, STAT_SKATER, skate,1000,1, skate,1,4,PED_TYPE_GEN,VOICE_GEN_WFYRO ,VOICE_GEN_WFYRO
93, WFYST, WFYST, CIVFEMALE, STAT_STREET_GIRL, sexywoman,1983,1, null,4,6,PED_TYPE_GEN,VOICE_GEN_WFYST,VOICE_GEN_WFYST
94, WMORI, WMORI, CIVMALE, STAT_SUIT_GUY, man, 120C,0, man,10,10,PED_TYPE_GEN,VOICE_GEN_WMORI ,VOICE_GEN_WMORI
95, WMOST, WMOST, CIVMALE, STAT_OLD_GUY, man,1003,0, man,8,1,PED_TYPE_GEN,VOICE_GEN_WMOST ,VOICE_GEN_WMOST
96, WMYJG, WMYJG, CIVMALE, STAT_SENSIBLE_GUY, jogger,1000,0, null,9,9,PED_TYPE_GEN,VOICE_GEN_WMYJG ,VOICE_GEN_WMYJG
97, WMYLG, WMYlG, CIVMALE, STAT_GEEK_GUY, jogger,1000,0, null,9,9,PED_TYPE_GEN,VOICE_GEN_WMYLG ,VOICE_GEN_WMYLG
98, WMYRI, WMYRI, CIVMALE, STAT_SHOPPER, man, 120C,1, null,6,9,PED_TYPE_GEN,VOICE_GEN_WMYRI ,VOICE_GEN_WMYRI
99, WMYRO, WMYRO, CIVMALE, STAT_SKATER, skate,1000,0, skate,9,9,PED_TYPE_GEN,VOICE_GEN_WMYRO,VOICE_GEN_WMYRO
100, WMYCR, WMYCR, CRIMINAL, STAT_CRIMINAL, man, 110F,1, man,2,6,PED_TYPE_GEN,VOICE_GEN_WMYCR ,VOICE_GEN_WMYCR
101, WMYST, WMYST, CIVMALE, STAT_STREET_GUY, man,1983,1, null,4,3,PED_TYPE_GEN,VOICE_GEN_WMYST ,VOICE_GEN_WMYST
102, BALLAS1, BALLAS1, GANG1, STAT_GANG1, gang1, 110F,1, null,3,3,PED_TYPE_GANG,VOICE_GNG_BALLAS1 ,VOICE_GNG_BALLAS2
103, BALLAS2, BALLAS2, GANG1, STAT_GANG1, gang2, 110F,1, null,3,3,PED_TYPE_GANG,VOICE_GNG_BALLAS3 ,VOICE_GNG_BALLAS4
104, BALLAS3, BALLAS3, GANG1, STAT_GANG1, gang1, 110F,1, null,3,3,PED_TYPE_GANG,VOICE_GNG_BALLAS5 ,VOICE_GNG_BALLAS5
105, FAM1, FAM1, GANG2, STAT_GANG2, gang2, 110F,1, null,5,5,PED_TYPE_GANG,VOICE_GNG_FAM1 ,VOICE_GNG_FAM2
106, FAM2, FAM2, GANG2, STAT_GANG2, gang1, 110F,1, null,5,5,PED_TYPE_GANG,VOICE_GNG_FAM3 ,VOICE_GNG_FAM4
107, FAM3, FAM3, GANG2, STAT_GANG2, gang2, 110F,1, null,5,5,PED_TYPE_GANG,VOICE_GNG_FAM5 ,VOICE_GNG_FAM5
108, LSV1, LSV1, GANG3, STAT_GANG3, gang1, 110F,1, null,9,2,PED_TYPE_GANG,VOICE_GNG_LSV1 ,VOICE_GNG_LSV2
109, LSV2, LSV2, GANG3, STAT_GANG3, gang2, 110F,1, null,9,2,PED_TYPE_GANG,VOICE_GNG_LSV3 ,VOICE_GNG_LSV4
110, LSV3, LSV3, GANG3, STAT_GANG3, gang1, 110F,1, null,9,2,PED_TYPE_GANG,VOICE_GNG_LSV5 ,VOICE_GNG_LSV5
111, MAFFA, MAFFA, CRIMINAL, STAT_CRIMINAL, man, 110F,1, null,2,2,PED_TYPE_GEN,VOICE_GEN_MAFFA ,VOICE_GEN_MAFFA
112, MAFFB, MAFFB, CRIMINAL, STAT_CRIMINAL, man, 110F,1, null,2,2,PED_TYPE_GEN,VOICE_GEN_MAFFB ,VOICE_GEN_MAFFB
113, MAFBOSS, MAFBOSS, CRIMINAL, STAT_CRIMINAL, man, 110F,1, null,2,2,PED_TYPE_GANG,VOICE_GNG_MAFBOSS ,VOICE_GNG_MAFBOSS
114, VLA1, VLA1, GANG8, STAT_GANG8, gang1, 110F,1, man,0,0,PED_TYPE_GANG,VOICE_GNG_VLA1 ,VOICE_GNG_VLA2
115, VLA2, VLA2, GANG8, STAT_GANG8, gang2, 110F,1, man,0,0,PED_TYPE_GANG,VOICE_GNG_VLA3 ,VOICE_GNG_VLA4
116, VLA3, VLA3, GANG8, STAT_GANG8, gang1, 110F,1, man,0,0,PED_TYPE_GANG,VOICE_GNG_VLA5 ,VOICE_GNG_VLA5
117, TRIADA, TRIADA, GANG7, STAT_GANG7, man, 110F,1, man,4,4,PED_TYPE_GANG,VOICE_GNG_STRI1 ,VOICE_GNG_STRI5
118, TRIADB, TRIADB, GANG7, STAT_GANG7, man, 110F,1, man,4,4,PED_TYPE_GANG,VOICE_GNG_STRI1 ,VOICE_GNG_STRI1
120, TRIBOSS, TRIBOSS, GANG7, STAT_GANG7, man, 110F,1, man,4,4,PED_TYPE_GANG,VOICE_GNG_STRI1 ,VOICE_GNG_STRI1
121, DNB1, DNB1 , GANG5, STAT_GANG5, gang1, 110F,1, man,3,4,PED_TYPE_GANG,VOICE_GNG_DNB1 ,VOICE_GNG_DNB1
122, DNB2, DNB2 , GANG5, STAT_GANG5, gang2, 110F,1, man,3,4,PED_TYPE_GANG,VOICE_GNG_DNB2 ,VOICE_GNG_DNB2
123, DNB3, DNB3 , GANG5, STAT_GANG5, gang1, 110F,1, man,3,4,PED_TYPE_GANG,VOICE_GNG_DNB3 ,VOICE_GNG_DNB5
124, VMAFF1, VMAFF1, GANG6, STAT_GANG6, gang1, 110F,1, man,2,2,PED_TYPE_GANG,VOICE_GNG_VMAFF1 ,VOICE_GNG_VMAFF2
125, VMAFF2, VMAFF2, GANG6, STAT_GANG6, man, 110F,1, man,2,2,PED_TYPE_GANG,VOICE_GNG_VMAFF3 ,VOICE_GNG_VMAFF3
126, VMAFF3, VMAFF3, GANG6, STAT_GANG6, man, 110F,1, man,2,2,PED_TYPE_GANG,VOICE_GNG_VMAFF4 ,VOICE_GNG_VMAFF4
127, VMAFF4, VMAFF4, GANG6, STAT_GANG6, man, 110F,1, man,2,2,PED_TYPE_GANG,VOICE_GNG_VMAFF5 ,VOICE_GNG_VMAFF5
128, DNMYLC, DNMYLC, CIVMALE, STAT_TOUGH_GUY, man, 1FFF,0, man,2,1,PED_TYPE_GEN,VOICE_GEN_DNMYLC ,VOICE_GEN_DNMYLC
129, DNFOLC1, DNFOLC1, CIVFEMALE, STAT_COWARD, oldwoman,1003,0, man,10,2,PED_TYPE_GEN,VOICE_GEN_DNFOLC1,VOICE_GEN_DNFOLC1
130, DNFOLC2, DNFOLC2, CIVFEMALE, STAT_COWARD, oldwoman,1003,0, man,10,10,PED_TYPE_GEN,VOICE_GEN_DNFOLC2,VOICE_GEN_DNFOLC2
131, DNFYLC, DNFYLC, CIVFEMALE, STAT_COWARD, sexywoman, 1FFF,1, man,2,6,PED_TYPE_GEN,VOICE_GEN_DNFYLC ,VOICE_GEN_DNFYLC
132, DNMOLC1, DNMOLC1, CIVMALE, STAT_OLD_GUY, man,1003,0, man,1,10,PED_TYPE_GEN,VOICE_GEN_DNMOLC1,VOICE_GEN_DNMOLC1
133, DNMOLC2, DNMOLC2, CIVMALE, STAT_OLD_GUY, man,1003,0, man,10,2,PED_TYPE_GEN,VOICE_GEN_DNMOLC2 ,VOICE_GEN_DNMOLC2
134, SBMOTR2,SBMOTR2, CIVMALE, STAT_TRAMP_MALE, oldman,1000,0, man,1,4,PED_TYPE_GEN,VOICE_GEN_SBMOTR1,VOICE_GEN_SBMOTR2
135, SWMOTR2, SWMOTR2, CIVMALE, STAT_TRAMP_MALE, man,1000,0, man,1,4,PED_TYPE_GEN,VOICE_GEN_SWMOTR2,VOICE_GEN_SWMOTR2
136, SBMYTR3, SBMYTR3, CIVMALE, STAT_TRAMP_MALE, man,1000,0, man,1,4,PED_TYPE_GEN,VOICE_GEN_SBMYTR3 ,VOICE_GEN_SBMYTR3
137, SWMOTR3, SWMOTR3, CIVMALE, STAT_TRAMP_MALE, man,1000,0, man,1,4,PED_TYPE_GEN,VOICE_GEN_SWMOTR3,VOICE_GEN_SWMOTR3
138, WFYBE,  WFYBE, CIVFEMALE, STAT_COWARD, woman,1000,0, beach,1,4,PED_TYPE_GEN,VOICE_GEN_WFYBE ,VOICE_GEN_WFYBE
139, BFYBE,  BFYBE, CIVFEMALE, STAT_BEACH_GIRL, woman,1000,0, beach,1,4,PED_TYPE_GEN,VOICE_GEN_BFYBE ,VOICE_GEN_BFYBE
140, HFYBE,  HFYBE, CIVFEMALE, STAT_BEACH_GIRL, woman,1000,0, beach,1,4,PED_TYPE_GEN,VOICE_GEN_HFYBE ,VOICE_GEN_HFYBE
141, SOFYBU, SOFYBU, CIVFEMALE, STAT_SUIT_GIRL, busywoman, 120C,0, man,4,0,PED_TYPE_GEN,VOICE_GEN_SOFYBU,VOICE_GEN_SOFYBU
142, SBMYST, SBMYST, CIVMALE, STAT_STREET_GUY, man,1983,1, man,8,5,PED_TYPE_GEN,VOICE_GEN_SBMYST ,VOICE_GEN_SBMYST
143, SBMYCR, SBMYCR, CRIMINAL, STAT_CRIMINAL, gang1, 110F,1, man,5,0,PED_TYPE_GEN,VOICE_GEN_SBMYCR,VOICE_GEN_SBMYCR
144, BMYCG, bmycg, CRIMINAL, STAT_CRIMINAL, gang2, 110F,1, man,8,3,PED_TYPE_GEN,VOICE_GEN_BMYCG ,VOICE_GEN_BMYCG
145, WFYCRK, Wfycrk, CIVFEMALE, STAT_CRIMINAL, woman, 110F,1, man,4,3,PED_TYPE_GEN,VOICE_GEN_WFYCRK ,VOICE_GEN_WFYCRK
146, HMYCM, hmycm, CRIMINAL, STAT_CRIMINAL, man, 110F,1, man,8,10,PED_TYPE_GEN,VOICE_GEN_HMYCM ,VOICE_GEN_HMYCM
147, WMYBU, wmybu, CIVMALE, STAT_COWARD, man, 120C,1, man,6,3,PED_TYPE_GEN,VOICE_GEN_WMYBU,VOICE_GEN_WMYBU
148, BFYBU, bfybu, CIVFEMALE, STAT_SUIT_GIRL, busywoman, 120C,1, man,3,7,PED_TYPE_GEN,VOICE_GEN_BFYBU ,VOICE_GEN_BFYBU
150, WFYBU, wfybu, CIVFEMALE, STAT_SUIT_GIRL, busywoman, 120C,1, man,9,2,PED_TYPE_GEN,VOICE_GEN_WFYBU,VOICE_GEN_WFYBU
151, DWFYLC1, Dwfylc1, CIVFEMALE, STAT_TOUGH_GIRL, sexywoman,1983,1, man,1,1,PED_TYPE_GEN,VOICE_GEN_DWFYLC1 ,VOICE_GEN_DWFYLC2
152, WFYPRO, WFYpro, PROSTITUTE, STAT_PROSTITUTE, pro,1000,1, man,1,4,PED_TYPE_GEN,VOICE_GEN_WFYPRO,VOICE_GEN_WFYPRO
153, WMYCONB, wmyconb , CIVMALE, STAT_SUIT_GUY, man, 170F,1, man,6,2,PED_TYPE_GEN,VOICE_GEN_WMYCONB ,VOICE_GEN_WMYCONB
154, WMYBE, wmybe , CIVMALE, STAT_SENSIBLE_GUY, man,1000,1, man,1,4,PED_TYPE_GEN,VOICE_GEN_WMYBE ,VOICE_GEN_WMYBE
155, WMYPIZZ, wmypizz , CIVMALE, STAT_SENSIBLE_GUY, man,1000,1, man,1,4,PED_TYPE_GFD,VOICE_GFD_WMYPIZZ ,VOICE_GFD_WMYPIZZ
156, BMOBAR, bmobar , CIVMALE, STAT_OLD_GUY, man,1000,0, man,1,4,PED_TYPE_GFD,VOICE_GFD_BMOBAR ,VOICE_GFD_BMOBAR
157, CWFYHB, cwfyhb , CIVFEMALE, STAT_TOUGH_GIRL, woman,1000,1, man,1,4,PED_TYPE_GEN,VOICE_GEN_CWFYHB1,VOICE_GEN_CWFYHB1
158, CWMOFR, cwmofr , CIVMALE, STAT_OLD_GUY, man,1000,0, man,1,4,PED_TYPE_GEN,VOICE_GEN_CWMOFR1,VOICE_GEN_CWMOFR1
159, CWMOHB1, cwmohb1 , CIVMALE, STAT_OLD_GUY, man, 110F,0, man,1,1,PED_TYPE_GEN,VOICE_GEN_CWMOHB1,VOICE_GEN_CWMOHB1
160, CWMOHB2, cwmohb2 , CIVMALE, STAT_OLD_GUY, oldman,1983,0, man,1,1,PED_TYPE_GEN,VOICE_GEN_CWMOHB2,VOICE_GEN_CWMOHB2
161, CWMYFR, cwmyfr , CIVMALE, STAT_TOUGH_GUY, man,1983,1, man,1,6,PED_TYPE_GEN,VOICE_GEN_CWMYFR,VOICE_GEN_CWMYFR
162, CWMYHB1, cwmyhb1 , CIVMALE, STAT_TOUGH_GUY, oldman,1983,0, man,6,2,PED_TYPE_GEN,VOICE_GEN_CWMYHB1,VOICE_GEN_CWMYHB1
163, BMYBOUN, bmyboun , CIVMALE, STAT_TOUGH_GUY, man, 170F,1, man,5,8,PED_TYPE_GEN,VOICE_GEN_BMYBOUN ,VOICE_GEN_BMYBOUN
164, WMYBOUN, wmyboun , CIVMALE, STAT_TOUGH_GUY, man, 170F,1, man,5,6,PED_TYPE_GEN,VOICE_GEN_WMYBOUN ,VOICE_GEN_WMYBOUN
165, WMOMIB, wmomib , CIVMALE, STAT_SUIT_GUY, man, 120C,0, man,10,11,PED_TYPE_GEN,VOICE_GEN_WMOMIB ,VOICE_GEN_WMOMIB
166, BMYMIB, bmymib , CIVMALE, STAT_SUIT_GUY, man, 120C,0, man,11,10,PED_TYPE_GEN,VOICE_GEN_BMYMIB ,VOICE_GEN_BMYMIB
167, WMYBELL, wmybell , CIVMALE, STAT_SENSIBLE_GUY, man,1000,1, man,1,4,PED_TYPE_GFD,VOICE_GFD_WMYBELL ,VOICE_GFD_WMYBELL
168, BMOCHIL, bmochil , CIVMALE, STAT_SENSIBLE_GUY, man,1000,1, man,1,4,PED_TYPE_GEN,VOICE_GEN_BMOST ,VOICE_GEN_BMOST
169, SOFYRI, sofyri , CIVFEMALE, STAT_COWARD, sexywoman, 120C,1, man,6,4,PED_TYPE_GEN,VOICE_GEN_SOFYRI,VOICE_GEN_SOFYRI
170, SOMYST, somyst , CIVMALE, STAT_COWARD, man,1983,0, man,4,9,PED_TYPE_GEN,VOICE_GEN_SOMYST,VOICE_GEN_SOMYST
171, VWMYBJD, vwmybjd , CIVMALE, STAT_SUIT_GUY, man,1000,1, man,1,4,PED_TYPE_GEN,VOICE_GEN_VWMYBJD ,VOICE_GEN_VWMYBJD
172, VWFYCRP, vwfycrp , CIVFEMALE, STAT_SUIT_GIRL, busywoman,1000,1, man,1,4,PED_TYPE_GEN,VOICE_GEN_WFYCRP ,VOICE_GEN_WFYCRP
173, SFR1, SFR1 , GANG4, STAT_GANG4, gang1, 110F,1, man,8,8,PED_TYPE_GANG,VOICE_GNG_SFR1 ,VOICE_GNG_SFR2
174, SFR2, SFR2 , GANG4, STAT_GANG4, gang2, 110F,1, man,8,8,PED_TYPE_GANG,VOICE_GNG_SFR3 ,VOICE_GNG_SFR4
175, SFR3, SFR3 , GANG4, STAT_GANG4, gang1, 110F,1, man,8,8,PED_TYPE_GANG,VOICE_GNG_SFR5 ,VOICE_GNG_SFR5
176, BMYBAR,  BMYBAR , CIVMALE, STAT_SENSIBLE_GUY, man,1000,1, man,1,4,PED_TYPE_GFD,VOICE_GFD_BMYBARB ,VOICE_GFD_BMYBARB
177, WMYBAR,  WMYBAR , CIVMALE, STAT_SENSIBLE_GUY, man,1000,1, man,1,4,PED_TYPE_GFD,VOICE_GFD_WMYBARB ,VOICE_GFD_WMYBARB
178, WFYSEX,  WFYSEX , CIVFEMALE, STAT_STREET_GIRL, sexywoman,1000,1, null,1,4,PED_TYPE_GEN,VOICE_GEN_NOVOICE ,VOICE_GEN_NOVOICE
179, WMYAMMO, WMYAMMO , CIVMALE, STAT_TOUGH_GUY, man, 1000,1, man,1,4,PED_TYPE_GFD,VOICE_GFD_WMYAMMO ,VOICE_GFD_WMYAMMO
180, BMYTATT, BMYTATT , CIVMALE, STAT_TOUGH_GUY, man, 1000,1, man,1,4,PED_TYPE_GFD,VOICE_GFD_BMYTATT ,VOICE_GFD_BMYTATT
181, VWMYCR,  VWMYCR , CRIMINAL, STAT_CRIMINAL, man, 110F,1, man,2,9,PED_TYPE_GEN,VOICE_GEN_VWMYCR,VOICE_GEN_VWMYCR
182, VBMOCD,  VBMOCD , CIVMALE, STAT_TAXIDRIVER, man, 0040,0, null,8,9,PED_TYPE_GEN,VOICE_GEN_VBMOCD,VOICE_GEN_VBMOCD
183, VBMYCR,  VBMYCR , CRIMINAL, STAT_CRIMINAL, man, 110F,1, man,5,0,PED_TYPE_GEN,VOICE_GEN_VBMYCR,VOICE_GEN_VBMYCR
184, VHMYCR,  VHMYCR , CRIMINAL, STAT_CRIMINAL, man, 110F,1, man,0,3,PED_TYPE_GEN,VOICE_GEN_VHMYCR,VOICE_GEN_VHMYCR
185, SBMYRI,  SBMYRI , CIVMALE, STAT_STREET_GUY, man, 120C,1, null,7,4,PED_TYPE_GEN,VOICE_GEN_SBMYRI,VOICE_GEN_SBMYRI
186, SOMYRI,  SOMYRI , CIVMALE, STAT_SUIT_GUY, man, 120C,1, null,4,0,PED_TYPE_GEN,VOICE_GEN_SOMYRI,VOICE_GEN_SOMYRI
187, SOMYBU,  SOMYBU , CIVMALE, STAT_SUIT_GUY, man, 120C,1, man,4,4,PED_TYPE_GEN,VOICE_GEN_SOMYBU,VOICE_GEN_SOMYBU
188, SWMYST,  SWMYST , CIVMALE, STAT_TOURIST, man,1983,1, null,0,3,PED_TYPE_GEN,VOICE_GEN_SWMYST ,VOICE_GEN_SWMYST
189, WMYVA,   WMYVA , CIVMALE, STAT_STREET_GUY, man,1983,1, null,6,2,PED_TYPE_GEN,VOICE_GEN_WMYVA ,VOICE_GEN_WMYVA
190, COPGRL3, COPGRL3 , CIVFEMALE, STAT_STREET_GIRL, busywoman, 1FFF,0, null,0,3,PED_TYPE_GFD,VOICE_GFD_BARBARA ,VOICE_GFD_BARBARA
191, GUNGRL3, GUNGRL3 , CIVFEMALE, STAT_STREET_GIRL, woman, 1FFF,0, null,0,3,PED_TYPE_GFD,VOICE_GFD_HELENA ,VOICE_GFD_HELENA
192, MECGRL3, MECGRL3 , CIVFEMALE, STAT_STREET_GIRL, sexywoman, 1FFF,0, null,0,3,PED_TYPE_GFD,VOICE_GFD_MICHELLE ,VOICE_GFD_MICHELLE
193, NURGRL3, NURGRL3 , CIVFEMALE, STAT_SUIT_GIRL, sexywoman, 1FFF,0, null,0,3,PED_TYPE_GFD,VOICE_GFD_KATIE ,VOICE_GFD_KATIE
194, CROGRL3, CROGRL3 , CIVFEMALE, STAT_SUIT_GIRL, sexywoman, 1FFF,0, null,0,3,PED_TYPE_GFD,VOICE_GFD_MILLIE ,VOICE_GFD_MILLIE
195, GANGRL3, GANGRL3 , CIVFEMALE, STAT_STREET_GIRL, woman, 1FFF,0, null,0,3,PED_TYPE_GFD,VOICE_GFD_DENISE ,VOICE_GFD_DENISE
196, CWFOFR,   CWFOFR , CIVFEMALE, STAT_COWARD, oldwoman,1003,0, null,1,1,PED_TYPE_GEN,VOICE_GEN_CWFOFR,VOICE_GEN_CWFOFR
197, CWFOHB,   CWFOHB , CIVFEMALE, STAT_OLD_GIRL, oldwoman,1003,0, null,1,1,PED_TYPE_GEN,VOICE_GEN_CWFOHB,VOICE_GEN_CWFOHB
198, CWFYFR1,  CWFYFR1 , CIVFEMALE, STAT_TOUGH_GIRL, woman,1983,0, null,2,1,PED_TYPE_GEN,VOICE_GEN_CWFYFR1,VOICE_GEN_CWFYFR1
199, CWFYFR2,  CWFYFR2 , CIVFEMALE, STAT_STREET_GIRL, woman,1983,0, null,1,1,PED_TYPE_GEN,VOICE_GEN_CWFYFR2,VOICE_GEN_CWFYFR2
200, CWMYHB2,  CWMYHB2 , CIVMALE, STAT_TOUGH_GUY, man,1983,1, null,1,1,PED_TYPE_GEN,VOICE_GEN_CWMYHB2,VOICE_GEN_CWMYHB2
201, DWFYLC2,  DWFYLC2 , CIVFEMALE, STAT_STREET_GIRL, woman,1983,0, null,6,2,PED_TYPE_GEN,VOICE_GEN_DWFYLC2 ,VOICE_GEN_DWFYLC2
202, DWMYLC2,  DWMYLC2 , CIVMALE, STAT_TOUGH_GUY, man,1983,1, null,6,2,PED_TYPE_GEN,VOICE_GEN_DWMYLC2,VOICE_GEN_DWMYLC2
203, OMYKARA,  OMYKARA , CIVMALE, STAT_TOUGH_GUY, man, 1FFF,0, null,0,7,PED_TYPE_GEN,VOICE_GEN_NOVOICE ,VOICE_GEN_NOVOICE
204, WMYKARA,  WMYKARA , CIVMALE, STAT_TOUGH_GUY, man, 1FFF,0, null,2,0,PED_TYPE_GEN,VOICE_GEN_NOVOICE ,VOICE_GEN_NOVOICE
205, WFYBURG,  WFYBURG , CIVFEMALE, STAT_STREET_GIRL, woman, 1FFF,1, null,0,3,PED_TYPE_GFD,VOICE_GFD_WFYBURG ,VOICE_GFD_WFYBURG
206, VWMYCD,   VWMYCD , CIVMALE, STAT_TAXIDRIVER, man,0040,0, null,6,5,PED_TYPE_GEN,VOICE_GEN_VWMYCD ,VOICE_GEN_VWMYCD
207, VHFYPRO,   VHFYPRO , PROSTITUTE, STAT_PROSTITUTE, pro,1000,1, man,1,4,PED_TYPE_GEN,VOICE_GEN_VHFYPRO ,VOICE_GEN_VHFYPRO
209, OMONOOD,   OMONOOD , CIVMALE, STAT_OLD_GUY, oldman, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_OMOST ,VOICE_GEN_OMOST
210, OMOBOAT,   OMOBOAT , CIVMALE, STAT_OLD_GUY, oldman, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_OMOBOAT ,VOICE_GEN_OMOBOAT
211, WFYCLOT,   WFYCLOT , CIVFEMALE, STAT_STREET_GIRL, woman, 1FFF,0, null,1,4,PED_TYPE_GFD,VOICE_GFD_WFYCLOT ,VOICE_GFD_WFYCLOT
212, VWMOTR1,   VWMOTR1 , CIVMALE, STAT_TRAMP_MALE, man,1000,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_VWMOTR1,VOICE_GEN_VWMOTR1
213, VWMOTR2,   VWMOTR2 , CIVMALE, STAT_TRAMP_MALE, man,1000,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_VWMOTR2,VOICE_GEN_VWMOTR2
214, VWFYWAI,   VWFYWAI , CIVFEMALE, STAT_STREET_GIRL, woman, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_VWFYWAI ,VOICE_GEN_VWFYWAI
215, SBFORI,   SBFORI , CIVFEMALE, STAT_COWARD, woman, 120C,0, null,9,10,PED_TYPE_GEN,VOICE_GEN_SBFORI,VOICE_GEN_SBFORI
216, SWFYRI,   SWFYRI , CIVFEMALE, STAT_SHOPPER, woman, 120C,0, null,4,6,PED_TYPE_GEN,VOICE_GEN_SWFYRI ,VOICE_GEN_SWFYRI
217, WMYCLOT,  WMYCLOT , CIVMALE, STAT_STREET_GUY, man, 1FFF,1, null,1,4,PED_TYPE_GFD,VOICE_GFD_WMYCLOT ,VOICE_GFD_WMYCLOT
218, SBFOST,   SBFOST , CIVFEMALE, STAT_STREET_GIRL, woman, 1003,0, null,8,9,PED_TYPE_GEN,VOICE_GEN_SBFOST ,VOICE_GEN_SBFOST
219, SBFYRI,   SBFYRI , CIVFEMALE, STAT_COWARD, woman, 120C,0, null,7,4,PED_TYPE_GEN,VOICE_GEN_SBFYRI,VOICE_GEN_SBFYRI
220, SBMOCD,   SBMOCD , CIVMALE, STAT_TAXIDRIVER, man, 0040,0, null,0,0,PED_TYPE_GEN,VOICE_GEN_SBMOCD,VOICE_GEN_SBMOCD
221, SBMORI,   SBMORI , CIVMALE, STAT_SUIT_GUY, man, 120C,1, null,8,0,PED_TYPE_GEN,VOICE_GEN_SBMORI ,VOICE_GEN_SBMORI
222, SBMOST,   SBMOST , CIVMALE, STAT_STREET_GUY, man, 1003,0, null,0,8,PED_TYPE_GEN,VOICE_GEN_SBMOST ,VOICE_GEN_SBMOST
223, SHMYCR,   SHMYCR , CRIMINAL, STAT_CRIMINAL, man, 110F,1, null,4,9,PED_TYPE_GEN,VOICE_GEN_SHMYCR ,VOICE_GEN_SHMYCR
224, SOFORI,   SOFORI , CIVFEMALE, STAT_OLD_GIRL, woman, 120C,0, null,1,10,PED_TYPE_GEN,VOICE_GEN_SOFORI,VOICE_GEN_SOFORI
225, SOFOST,   SOFOST , CIVFEMALE, STAT_STREET_GIRL, woman, 1003,0, null,9,10,PED_TYPE_GEN,VOICE_GEN_SOFOST,VOICE_GEN_SOFOST
226, SOFYST,   SOFYST , CIVFEMALE, STAT_STREET_GIRL, woman, 1003,1, null,4,7,PED_TYPE_GEN,VOICE_GEN_SOFYST,VOICE_GEN_SOFYST
227, SOMOBU,   SOMOBU , CIVMALE, STAT_SUIT_GUY, man, 120C,0, null,10,10,PED_TYPE_GEN,VOICE_GEN_SOMOBU,VOICE_GEN_SOMOBU
228, SOMORI,   SOMORI , CIVMALE, STAT_COWARD, man, 120C,0, null,9,3,PED_TYPE_GEN,VOICE_GEN_SOMORI,VOICE_GEN_SOMORI
229, SOMOST,   SOMOST , CIVMALE, STAT_STREET_GUY, man, 1003,0, null,9,2,PED_TYPE_GEN,VOICE_GEN_SOMOST,VOICE_GEN_SOMOST
230, SWMOTR5,  SWMOTR5 , CIVMALE, STAT_TRAMP_MALE, man, 1000,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_SWMOTR5,VOICE_GEN_SWMOTR5
231, SWFORI,   SWFORI , CIVFEMALE, STAT_COWARD, woman, 120C,0, null,10,1,PED_TYPE_GEN,VOICE_GEN_SWFORI,VOICE_GEN_SWFORI
232, SWFOST,   SWFOST , CIVFEMALE, STAT_STREET_GIRL, woman, 1003,0, null,7,10,PED_TYPE_GEN,VOICE_GEN_SWFOST,VOICE_GEN_SWFOST
233, SWFYST,   SWFYST,  CIVFEMALE, STAT_STREET_GIRL, woman, 1983,1, null,7,3,PED_TYPE_GEN,VOICE_GEN_SWFYST ,VOICE_GEN_SWFYST
234, SWMOCD,   SWMOCD , CIVMALE, STAT_TAXIDRIVER, man, 0040,0, null,2,9,PED_TYPE_GEN,VOICE_GEN_SWMOCD,VOICE_GEN_SWMOCD
235, SWMORI,   SWMORI , CIVMALE, STAT_SUIT_GUY, man, 120C,0, null,7,0,PED_TYPE_GEN,VOICE_GEN_SWMORI,VOICE_GEN_SWMORI
236, SWMOST,   SWMOST , CIVMALE, STAT_STREET_GUY, man, 1983,0, null,2,1,PED_TYPE_GEN,VOICE_GEN_SWMOST ,VOICE_GEN_SWMOST
237, SHFYPRO,  SHFYPRO , PROSTITUTE, STAT_PROSTITUTE, pro, 1000,1, null,1,4,PED_TYPE_GEN,VOICE_GEN_SHFYPRO ,VOICE_GEN_SHFYPRO
238, SBFYPRO,  SBFYPRO , PROSTITUTE, STAT_PROSTITUTE, pro, 1000,1, null,1,4,PED_TYPE_GEN,VOICE_GEN_SBFYPRO,VOICE_GEN_SBFYPRO
239, SWMOTR4,  SWMOTR4 , CIVMALE, STAT_TRAMP_MALE, man, 1000,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_SWMOTR4,VOICE_GEN_SWMOTR4
240, SWMYRI,   SWMYRI , CIVMALE, STAT_COWARD, man, 120C,1, null,4,4,PED_TYPE_GEN,VOICE_GEN_SWMYRI ,VOICE_GEN_SWMYRI
241, SMYST,    SMYST , CIVMALE, STAT_STREET_GUY, man, 1983, 1, null, 0,5,PED_TYPE_GEN,VOICE_GEN_SMYST ,VOICE_GEN_SMYST
242, SMYST2,   SMYST2, CIVMALE, STAT_STREET_GUY, man, 130C, 1, null, 0,8,PED_TYPE_GEN,VOICE_GEN_SMYST2 ,VOICE_GEN_SMYST2
243, SFYPRO,   SFYPRO , PROSTITUTE, STAT_PROSTITUTE, pro, 1000, 1, null, 1,4,PED_TYPE_GEN,VOICE_GEN_SFYPRO ,VOICE_GEN_SFYPRO
244, VBFYST2,   VBFYST2 , CIVFEMALE, STAT_STREET_GIRL, sexywoman, 1000, 1, null, 1,4,PED_TYPE_GEN,VOICE_GEN_VBFYST2 ,VOICE_GEN_VBFYST2
245, VBFYPRO,   VBFYPRO , PROSTITUTE, STAT_PROSTITUTE, pro, 1000, 1, null, 1,4,PED_TYPE_GEN,VOICE_GEN_VBFYPRO ,VOICE_GEN_VBFYPRO
246, VHFYST3,   VHFYST3 , CIVFEMALE, STAT_STREET_GIRL, sexywoman, 1000, 1, null, 1,4,PED_TYPE_GEN,VOICE_GEN_VHFYST3 ,VOICE_GEN_VHFYST3
247, BIKERA,   BIKERA , CIVMALE, STAT_TOUGH_GUY, man, 0,1, null,5,2,PED_TYPE_GEN,VOICE_GEN_BIKERA ,VOICE_GEN_BIKERA
248, BIKERB,   BIKERB , CIVMALE, STAT_TOUGH_GUY, man, 0,1, null,2,5,PED_TYPE_GEN,VOICE_GEN_BIKERB ,VOICE_GEN_BIKERB
249, BMYPIMP,   BMYPIMP , CIVMALE, STAT_STREET_GUY, man, 130C,1, null,3,7,PED_TYPE_GEN,VOICE_GEN_BMYPI ,VOICE_GEN_BMYPI
250, SWMYCR,   SWMYCR , CRIMINAL, STAT_CRIMINAL, man, 110F,1, man,6,0,PED_TYPE_GEN,VOICE_GEN_SWMYCR ,VOICE_GEN_SWMYCR
251, WFYLG,    WFYLG , CIVFEMALE, STAT_BEACH_GIRL, woman,1000,0, beach,1,4,PED_TYPE_GEN,VOICE_GEN_WFYLG ,VOICE_GEN_WFYLG
252, WMYVA2,   WMYVA2 , CIVMALE, STAT_STREET_GUY, man, 1983, 1, null, 9,7,PED_TYPE_GEN,VOICE_GEN_WMYVA ,VOICE_GEN_WMYVA
253, BMOSEC,   BMOSEC , CIVMALE, STAT_OLD_GUY, man, 1003,0, null,8,0,PED_TYPE_GEN,VOICE_GEN_BMOSEC ,VOICE_GEN_BMOSEC
254, BIKDRUG,  BIKDRUG , CIVMALE, STAT_CRIMINAL, man, 0,1, null,6,2,PED_TYPE_GEN,VOICE_GEN_BIKDRUG ,VOICE_GEN_BIKDRUG
255, WMYCH,    WMYCH , CIVMALE, STAT_TOUGH_GUY, man, 0,1, null,7,0,PED_TYPE_GEN,VOICE_GEN_WMYCH ,VOICE_GEN_WMYCH
256, SBFYSTR,  SBFYSTR , CIVFEMALE, STAT_STREET_GIRL, sexywoman, 130C,0, null,3,7,PED_TYPE_GEN,VOICE_GEN_SBFYST ,VOICE_GEN_SBFYST
257, SWFYSTR,  SWFYSTR , CIVFEMALE, STAT_STREET_GIRL, sexywoman, 130C,0, null,5,9,PED_TYPE_GEN,VOICE_GEN_SWFYST ,VOICE_GEN_SWFYST
258, HECK1,  HECK1 , CIVMALE, STAT_TOUGH_GUY, man, 0,1, null,7,0,PED_TYPE_GEN,VOICE_GEN_NOVOICE ,VOICE_GEN_NOVOICE
259, HECK2,  HECK2 , CIVMALE, STAT_TOUGH_GUY, man, 0,1, null,7,0,PED_TYPE_GEN,VOICE_GEN_NOVOICE ,VOICE_GEN_NOVOICE
260, BMYCON, BMYCON  , CIVMALE, STAT_TOUGH_GUY, man, 0,1, null,7,0,PED_TYPE_GEN,VOICE_GEN_BMYCON ,VOICE_GEN_BMYCON
261, WMYCD1, WMYCD1  , CIVMALE, STAT_TAXIDRIVER, man, 0040,1, null,6,1,PED_TYPE_GEN,VOICE_GEN_WMYCD1 ,VOICE_GEN_WMYCD1
262, BMOCD, BMOCD  , CIVMALE, STAT_TAXIDRIVER, man, 0040,0, null,8,0,PED_TYPE_GEN,VOICE_GEN_BMOCD ,VOICE_GEN_BMOCD
263, VWFYWA2,   VWFYWA2 , CIVFEMALE, STAT_STREET_GIRL, woman, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_VWFYWAI ,VOICE_GEN_VWFYWAI
264, WMOICE,   WMOICE , CIVMALE, STAT_STREET_GUY, man, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_NOVOICE ,VOICE_GEN_NOVOICE
265, TENPEN,TENPEN, CIVMALE, STAT_STD_MISSION, man, 1FFF, 0, null, 9,9, PED_TYPE_SPC, VOICE_GEN_NOVOICE , VOICE_GEN_NOVOICE
266, PULASKI,PULASKI, CIVMALE, STAT_STD_MISSION, man, 1FFF, 0, null, 9,9, PED_TYPE_SPC, VOICE_GEN_NOVOICE , VOICE_EMG_PULASKI
267, HERN,HERN, CIVMALE, STAT_STD_MISSION, man, 1FFF, 0, null, 9,9, PED_TYPE_SPC, VOICE_GEN_NOVOICE , VOICE_GEN_NOVOICE
268, DWAYNE,DWAYNE, CIVMALE, STAT_STD_MISSION, man, 1FFF, 0, null, 9,9, PED_TYPE_SPC, VOICE_GEN_NOVOICE , VOICE_GEN_NOVOICE
269, SMOKE,SMOKE, CIVMALE, STAT_STD_MISSION, man, 1FFF, 0, null, 9,9, PED_TYPE_SPC, VOICE_GNG_SMOKE , VOICE_GNG_SMOKE
270, SWEET,SWEET, CIVMALE, STAT_STD_MISSION, man, 1FFF, 0, null, 9,9, PED_TYPE_SPC, VOICE_GNG_SWEET , VOICE_GNG_SWEET
271, RYDER2,RYDER2, CIVMALE, STAT_STD_MISSION, man, 1FFF, 0, null, 9,9, PED_TYPE_SPC, VOICE_GNG_RYDER , VOICE_GNG_RYDER
272, FORELLI,FORELLI, CIVMALE, STAT_STD_MISSION, man, 1FFF, 0, null, 9,9, PED_TYPE_SPC, VOICE_GNG_MAFBOSS , VOICE_GNG_MAFBOSS
274, laemt1, laemt1, MEDIC, STAT_MEDIC, swat, 1FFF, 0, medic, 9,9, PED_TYPE_EMG,VOICE_EMG_EMT1 ,VOICE_EMG_EMT5
275, lvemt1, lvemt1, MEDIC, STAT_MEDIC, swat, 1FFF, 0, medic, 9,9, PED_TYPE_EMG,VOICE_EMG_EMT1 ,VOICE_EMG_EMT5
276, sfemt1, sfemt1, MEDIC, STAT_MEDIC, swat, 1FFF, 0, medic, 9,9, PED_TYPE_EMG,VOICE_EMG_EMT1 ,VOICE_EMG_EMT5
277, lafd1, lafd1, FIREMAN, STAT_FIREMAN, swat, 1FFF, 0, null, 9,9, PED_TYPE_GEN,VOICE_GEN_NOVOICE ,VOICE_GEN_NOVOICE
278, lvfd1, lvfd1, FIREMAN, STAT_FIREMAN, swat, 1FFF, 0, null, 9,9, PED_TYPE_GEN,VOICE_GEN_NOVOICE ,VOICE_GEN_NOVOICE
279, sffd1, sffd1, FIREMAN, STAT_FIREMAN, swat, 1FFF, 0, null, 9,9, PED_TYPE_GEN,VOICE_GEN_NOVOICE ,VOICE_GEN_NOVOICE
280, lapd1, lapd1, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_LAPD1 ,VOICE_EMG_LAPD8
281, sfpd1, sfpd1, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_SFPD1 ,VOICE_EMG_SFPD5
282, lvpd1, lvpd1, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_LVPD1 ,VOICE_EMG_LVPD5
283, csher, csher, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_RCOP1 ,VOICE_EMG_RCOP4
284, lapdm1, lapdm1, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_MCOP1 ,VOICE_EMG_MCOP6
285, swat, swat, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_SWAT1 ,VOICE_EMG_SWAT6
286, fbi, fbi, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_FBI2 ,VOICE_EMG_FBI6
287, army, army, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG, VOICE_EMG_ARMY1 ,VOICE_EMG_ARMY3
288, dsher, dsher, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_RCOP1 ,VOICE_EMG_RCOP4
290, ROSE, ROSE, CIVMALE, STAT_STREET_GUY, man, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_NOVOICE, VOICE_GEN_NOVOICE
291, PAUL, PAUL, CIVMALE, STAT_STREET_GUY, man, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_NOVOICE, VOICE_GEN_NOVOICE
292, CESAR, CESAR, CIVMALE, STAT_STREET_GUY, man, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GNG_CESAR, VOICE_GNG_CESAR
293, OGLOC, OGLOC, CIVMALE, STAT_STREET_GUY, man, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GNG_OGLOC, VOICE_GNG_OGLOC
294, WUZIMU, WUZIMU, CIVMALE, STAT_STREET_GUY, man, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GNG_WOOZIE, VOICE_GNG_WOOZIE
295, TORINO, TORINO, CIVMALE, STAT_STREET_GUY, man, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GNG_TORENO, VOICE_GNG_TORENO
296, JIZZY, JIZZY, CIVMALE, STAT_STREET_GUY, man, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GNG_JIZZY, VOICE_GNG_JIZZY
297, MADDOGG, MADDOGG, CIVMALE, STAT_STREET_GUY, man, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_NOVOICE, VOICE_GEN_NOVOICE
298, CAT, CAT, CIVMALE, STAT_STREET_GUY, man, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GFD_CATALINA, VOICE_GFD_CATALINA
299, CLAUDE, CLAUDE, CIVMALE, STAT_STREET_GUY, man, 1FFF,0, null,1,4,PED_TYPE_GEN,VOICE_GEN_NOVOICE, VOICE_GEN_NOVOICE
300, lapdna, lapd1, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_LAPD1 ,VOICE_EMG_LAPD8
301, sfpdna, sfpd1, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_SFPD1 ,VOICE_EMG_SFPD5
302, lvpdna, lvpd1, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_LVPD1 ,VOICE_EMG_LVPD5
303, lapdpc, lapdpc, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_LAPD1 ,VOICE_EMG_LAPD8
304, lapdpd, lapdpd, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_LAPD1 ,VOICE_EMG_LAPD8
305, lvpdpc, lvpdpc, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_LVPD1 ,VOICE_EMG_LVPD5
306, WFYCLPD, WFYCLPD, CIVFEMALE, STAT_STREET_GIRL, woman, 1FFF,0, null,1,4,PED_TYPE_GFD,VOICE_GFD_WFYCLOT ,VOICE_GFD_WFYCLOT
307, VBFYCPD, VBFYCPD, CIVFEMALE, STAT_SUIT_GIRL, woman, 130C,0, null,3,7,PED_TYPE_GEN,VOICE_GEN_BFYCRP ,VOICE_GEN_BFYCRP
308, WFYCLEM, WFYCLEM, CIVFEMALE, STAT_STREET_GIRL, sexywoman,1983,1, null,4,6,PED_TYPE_GEN,VOICE_GEN_WFYST,VOICE_GEN_WFYST
309, WFYCLLV, WFYCLLV, CIVFEMALE, STAT_STREET_GIRL, woman, 1FFF,0, null,1,4,PED_TYPE_GFD,VOICE_GFD_WFYCLOT ,VOICE_GFD_WFYCLOT
310, csherna, csherna, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_RCOP1 ,VOICE_EMG_RCOP4
311, dsherna, dsherna, COP, STAT_COP, swat, 1FFF, 0, null, 9,9, PED_TYPE_EMG,VOICE_EMG_RCOP1 ,VOICE_EMG_RCOP4]]

local freeID = {}

local tbl_peds = {}

function main()
	local folder =  getGameDirectory() .."\\modloader\\RandomChar\\RandomChar.ide"
	if not doesFileExist(folder) then GeneratedIDE() end

	repeat wait(0) until memory.read(0xC8D4C0, 4, false) == 9
	repeat wait(0) until fixed_camera_to_skin()

	while true do wait(0)
		for i = 1, #getAllChars() do

			if tbl_peds[getAllChars()[i]] ~= nil then goto continue end
			tbl_peds[getAllChars()[i]] = {[1] = getAllChars()[i], [2] = false, [3] = getCharModel(getAllChars()[i])}
			::continue::

			if tbl_peds[getAllChars()[i]] ~= nil and not tbl_peds[getAllChars()[i]][2] and config.chars[tostring(tbl_peds[getAllChars()[i]][3])] ~= nil then
				local need_tbl = config.chars[tostring(tbl_peds[getAllChars()[i]][3])]
				setCharModelId(tbl_peds[getAllChars()[i]][1], need_tbl[random(1, #need_tbl)])
				tbl_peds[getAllChars()[i]][2] = true
			end
		end
		for k, v in pairs(tbl_peds) do
			if not doesCharExist(k) then
				tbl_peds[k] = nil
			end
		end
	end

end

function fixed_camera_to_skin() -- проверка на приклепление камеры к скину
	return (memory.read(getModuleHandle('gta_sa.exe') + 0x76F053, 1, false) >= 1 and true or false)
end

function setCharModelId(pedHandle, modelId)
	lua_thread.create(function() wait(0)
		local charPtr = getCharPointer(pedHandle)
		local modelId = tonumber(modelId)

		if charPtr >= 1 and isModelAvailable(modelId) and isModelInCdimage(modelId) then
			if not hasModelLoaded(modelId) then
				requestModel(modelId)
				loadAllModelsNow()
			end
			ffi.cast("void (__thiscall *)(int, int)", 0x5E4880)(charPtr, modelId)
			-- if not isCharInAnyCar(pedHandle) then
				clearCharTasks(pedHandle)
			-- end
			markModelAsNoLongerNeeded(modelID)
		end
	end)
end

function GeneratedIDE()
	local folder =  getGameDirectory() .."\\modloader\\RandomChar\\RandomChar.ide"
	local folder_json =  getGameDirectory() .."\\moonloader\\config\\RandomChar.json"
	local folder_txt =  getGameDirectory() .."\\modloader\\RandomChar\\RandomChar.txt"
	local folder_custom =  getGameDirectory() .."\\modloader\\RandomChar\\CUSTOM.ide"
	os.remove(folder_json)
	os.remove(folder_custom)
	os.remove(folder_txt)
	for i = 1, 20000 do
		if not isModelAvailable(i) then
			freeID[#freeID+1] = i
		end
	end

	local file = io.open(folder, 'w')
	file:write(text_text)
	file:close()

	local test_tblasdaw = {}
	f = io.open(folder,"a+")
	for line in f:lines() do
		local v_1, v_2, v_3 = tostring(line):match('^(%d+),(.+),(.+,.+,.+,.+,.+,.+,.+,.+,.+,.+,.+)$')
		if v_1 ~= nil then
			test_tblasdaw[tonumber(v_1)] = v_3
		end
	end
	f:close()

	local file = io.open(folder, 'w')
	file:write("peds")
	file:close()

	f = io.open(folder,"a+")
	local tableOfLines = {}
	for line in f:lines() do
		if not line:find("^end$") then
			table.insert(tableOfLines, line)
		end
	end
	f:close()

	local file = io.open(folder, 'w')
	file:write('')
	file:close()

	for k, v in ipairs(testNameModel) do
		local folder_dff = getGameDirectory() .."\\modloader\\RandomChar\\" ..v.. "\\*.dff"
		local search, file = findFirstFile(folder_dff)
		local count = 0
		if file ~= nil then config.chars[tostring(k)] = {k} end
		while file do
			if file ~= (v..".dff") then
				count = count+1
				local no_dff = file:gsub("%.dff", "")
				local char_new = freeID[1] .. ", " .. no_dff .. ", " .. no_dff .. ", " .. test_tblasdaw[k]
				config.chars[tostring(k)][#config.chars[tostring(k)]+1] = tonumber(freeID[1])
				table.remove(freeID, 1)
				tableOfLines[#tableOfLines+1] = char_new
			end
			file = findNextFile(search)
		end
	end

	local file = io.open(folder, 'a')
	for i = 1, #tableOfLines do
		file:write(tableOfLines[i]..'\n')
	end
	file:write("end")
	file:close()

	local file = io.open(folder_custom, 'a')
	for i = 1, #tableOfLines do
		file:write(tableOfLines[i]..'\n')
	end
	file:write("end")
	file:close()

	local file = io.open(folder_txt, 'w')
	file:write("IDE data\\RandomChar.ide")
	file:close()

	savejson(convertTableToJsonString(config), "moonloader/config/RandomChar.json")
	callFunction(0x81E5E6, 4, 0, 0, u8:decode"[RU] Сформированы:\n	RandomChar.ide\\CUSTOM.ide\\RandomChar.txt\n	Необходимо перезапустить игру\n[EN] Generated\n	RandomChar.ide\\CUSTOM.ide\\RandomChar.txt\n	Need restart game", "RandomChar.lua", 0x00040000)
	os.execute('taskkill /IM gta_sa.exe /F')
end