local data_proxy = require "logic.data_proxy"

local M = {}

-- Singleton State
local state = {
    controller_url = nil,
    
    is_music_enabled = true,
    music_volume = 1.0,
    sfx_volume = 1.0,
    
    current_playlist_id = nil,
    current_playlist_tracks = {},
    current_track_index = 0,
    play_mode = "LINEAR", -- "LINEAR", "SHUFFLE", "LOOP_ONE"
    
    -- Crossfade State
    current_bgm_url = nil,
    next_bgm_url = nil,
    is_fading = false,
    fade_timer = 0,
    fade_duration = 2.0,
    fade_start_vol_current = 0,
    fade_target_vol_current = 0,
    fade_start_vol_next = 0,
    fade_target_vol_next = 0,
}

local SAVE_FILE = "tiny_dominion_audio_v1"

--- Initialize the audio manager state from save
function M.init()
    local save_path = sys.get_save_file("tiny_dominion", SAVE_FILE)
    local saved_state = sys.load(save_path)
    
    if saved_state and saved_state.initialized then
        state.is_music_enabled = saved_state.is_music_enabled
        state.music_volume = saved_state.music_volume
        state.sfx_volume = saved_state.sfx_volume
    end
    
    M.apply_volumes()
    print("[AudioManager] Initialized. Music enabled: " .. tostring(state.is_music_enabled))
end

--- Save audio preferences
function M.save_state()
    local save_path = sys.get_save_file("tiny_dominion", SAVE_FILE)
    sys.save(save_path, {
        initialized = true,
        is_music_enabled = state.is_music_enabled,
        music_volume = state.music_volume,
        sfx_volume = state.sfx_volume
    })
end

--- Register the central audio controller game object
function M.register_controller(url)
    state.controller_url = msg.url(url)
    state.controller_url.fragment = nil -- Point to the GO, not the script component
    print("[AudioManager] Controller registered at: " .. tostring(state.controller_url))
end

--- Apply volumes globally to Defold sound groups
function M.apply_volumes()
    if state.is_music_enabled then
        sound.set_group_gain(hash("music"), state.music_volume)
    else
        sound.set_group_gain(hash("music"), 0.0)
    end
    sound.set_group_gain(hash("sfx"), state.sfx_volume)
end

--- Toggle music on/off
function M.toggle_music(enabled)
    print("[AudioManager] Toggle music: " .. tostring(enabled))
    state.is_music_enabled = enabled
    M.apply_volumes()
    M.save_state()
    
    if enabled and state.current_playlist_id then
        M.play_playlist(state.current_playlist_id, state.play_mode)
    elseif not enabled then
        if state.current_bgm_url then
            sound.stop(state.current_bgm_url)
            state.current_bgm_url = nil
        end
        if state.next_bgm_url then
            sound.stop(state.next_bgm_url)
            state.next_bgm_url = nil
        end
        state.is_fading = false
    end
end

--- Play a specific playlist by ID
function M.play_playlist(playlist_id, mode)
    print("[AudioManager] Playing playlist: " .. tostring(playlist_id))
    local playlist_data = data_proxy.get_entry("playlist", playlist_id)
    if not playlist_data or not playlist_data.tracks or #playlist_data.tracks == 0 then
        print("[AudioManager] ERROR: Playlist not found or empty: " .. tostring(playlist_id))
        return
    end

    state.current_playlist_id = playlist_id
    state.play_mode = mode or "LINEAR"
    
    -- Copy tracks
    state.current_playlist_tracks = {}
    for _, track_id in ipairs(playlist_data.tracks) do
        table.insert(state.current_playlist_tracks, track_id)
    end

    if state.play_mode == "SHUFFLE" then
        -- Shuffle tracks
        for i = #state.current_playlist_tracks, 2, -1 do
            local j = math.random(i)
            state.current_playlist_tracks[i], state.current_playlist_tracks[j] = state.current_playlist_tracks[j], state.current_playlist_tracks[i]
        end
    end

    state.current_track_index = 1
    M.play_track_index(state.current_track_index, true)
end

--- Play the next track in the playlist
function M.play_next()
    print("[AudioManager] Play next track...")
    if not state.is_music_enabled or #state.current_playlist_tracks == 0 then return end

    if state.play_mode == "LOOP_ONE" then
        M.play_track_index(state.current_track_index, false)
    else
        state.current_track_index = state.current_track_index + 1
        if state.current_track_index > #state.current_playlist_tracks then
            state.current_track_index = 1 -- Loop back to start
        end
        M.play_track_index(state.current_track_index, false)
    end
end

-- Callback pour la fin de lecture
local function sound_done_callback(self, message_id, message, sender)
    if message_id == hash("sound_done") then
        print("[AudioManager] Sound finished: " .. tostring(sender))
        M.on_sound_done(sender)
    end
end

--- Internal: play specific track from list
function M.play_track_index(index, immediate)
    local track_id = state.current_playlist_tracks[index]
    local audio_data = data_proxy.get_entry("audio", track_id)
    
    if not audio_data then
        print("[AudioManager] ERROR: Audio data not found for track: " .. tostring(track_id))
        M.play_next()
        return
    end

    if not state.controller_url then
        print("[AudioManager] ERROR: Controller not registered, cannot play.")
        return
    end

    local track_url = msg.url(state.controller_url.socket, state.controller_url.path, track_id)
    local target_volume = audio_data.volume or 1.0
    
    print("[AudioManager] Starting track: " .. track_id .. " (Vol: " .. tostring(target_volume) .. ") URL: " .. tostring(track_url))

    if immediate then
        if state.current_bgm_url then
            sound.stop(state.current_bgm_url)
        end
        state.current_bgm_url = track_url
        sound.play(state.current_bgm_url, { gain = 0.05 }, sound_done_callback) -- Start very low
        
        state.is_fading = true
        state.fade_timer = 0
        state.fade_start_vol_current = 0.05
        state.fade_target_vol_current = target_volume
        state.fade_start_vol_next = 0
        state.fade_target_vol_next = 0
        state.next_bgm_url = nil
    else
        -- Crossfade
        state.next_bgm_url = track_url
        sound.play(state.next_bgm_url, { gain = 0.05 }, sound_done_callback)
        
        state.is_fading = true
        state.fade_timer = 0
        state.fade_start_vol_current = state.current_bgm_url and 1.0 or 0.0 
        state.fade_target_vol_current = 0.0
        state.fade_start_vol_next = 0.05
        state.fade_target_vol_next = target_volume
    end
end

--- Update loop for crossfading
function M.update(dt)
    if not state.is_fading then return end

    state.fade_timer = state.fade_timer + dt
    local t = state.fade_timer / state.fade_duration
    
    if t >= 1.0 then
        t = 1.0
        state.is_fading = false
        
        if state.next_bgm_url then
            if state.current_bgm_url then
                sound.stop(state.current_bgm_url)
            end
            state.current_bgm_url = state.next_bgm_url
            state.next_bgm_url = nil
            sound.set_gain(state.current_bgm_url, state.fade_target_vol_next)
        else
            if state.current_bgm_url then
                sound.set_gain(state.current_bgm_url, state.fade_target_vol_current)
            end
        end
        print("[AudioManager] Fade complete.")
    else
        -- Lerp
        if state.next_bgm_url then
            local vol_current = vmath.lerp(t, state.fade_start_vol_current, state.fade_target_vol_current)
            local vol_next = vmath.lerp(t, state.fade_start_vol_next, state.fade_target_vol_next)
            if state.current_bgm_url then sound.set_gain(state.current_bgm_url, vol_current) end
            sound.set_gain(state.next_bgm_url, vol_next)
        else
            local vol_current = vmath.lerp(t, state.fade_start_vol_current, state.fade_target_vol_current)
            if state.current_bgm_url then sound.set_gain(state.current_bgm_url, vol_current) end
        end
    end
end

--- Called when a sound finishes
function M.on_sound_done(sender)
    -- Important: s'assurer que sender est l'URL du morceau actuel
    -- sender peut être une URL absolue ou relative, on compare les hashes de path/fragment
    local s_url = msg.url(sender)
    local c_url = state.current_bgm_url and msg.url(state.current_bgm_url)

    if c_url and s_url.path == c_url.path and s_url.fragment == c_url.fragment then
        print("[AudioManager] Valid track end detected, playing next.")
        M.play_next()
    else
        print("[AudioManager] Sound finished but was not the current BGM or already fading.")
    end
end

--- SDK Focus Handling
function M.pause_all()
    sound.set_group_gain(hash("master"), 0.0)
end

function M.resume_all()
    sound.set_group_gain(hash("master"), 1.0)
end

return M
