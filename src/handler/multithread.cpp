#include <future>
#include <thread>
#include <utility>

#include "handler/fetch_context.h"
#include "handler/settings.h"
#include "utils/network.h"
#include "webget.h"
#include "multithread.h"
//#include "vfs.h"

//safety lock for multi-thread (shared_mutex: concurrent reads allowed)
std::shared_mutex on_emoji, on_rename, on_stream, on_time;

static std::shared_future<std::string> make_ready_future(std::string value)
{
    std::promise<std::string> promise;
    promise.set_value(std::move(value));
    return promise.get_future().share();
}

RegexMatchConfigs safe_get_emojis()
{
    std::shared_lock lock(on_emoji);
    return global.emojis;
}

RegexMatchConfigs safe_get_renames()
{
    std::shared_lock lock(on_rename);
    return global.renames;
}

RegexMatchConfigs safe_get_streams()
{
    std::shared_lock lock(on_stream);
    return global.streamNodeRules;
}

RegexMatchConfigs safe_get_times()
{
    std::shared_lock lock(on_time);
    return global.timeNodeRules;
}

void safe_set_emojis(RegexMatchConfigs data)
{
    std::unique_lock lock(on_emoji);
    global.emojis.swap(data);
}

void safe_set_renames(RegexMatchConfigs data)
{
    std::unique_lock lock(on_rename);
    global.renames.swap(data);
}

void safe_set_streams(RegexMatchConfigs data)
{
    std::unique_lock lock(on_stream);
    global.streamNodeRules.swap(data);
}

void safe_set_times(RegexMatchConfigs data)
{
    std::unique_lock lock(on_time);
    global.timeNodeRules.swap(data);
}

std::shared_future<std::string> fetchFileAsync(const std::string &path, const std::string &proxy, int cache_ttl, bool find_local, bool async, const std::string &user_agent, FetchContext context)
{
    // Helper lambda to call webGet with optional UA header
    auto do_webGet = [&](const std::string &url, const std::string &px, int ttl) -> std::string {
        if(user_agent.empty())
            return webGet(url, px, ttl, nullptr, nullptr, context);
        string_icase_map headers;
        headers["User-Agent"] = user_agent;
        return webGet(url, px, ttl, nullptr, &headers);
    };

    // Security check: block public requests from reading local files outside trusted paths
    auto canReadLocal = [&](const std::string &p) -> bool {
        if(!isPublicFetchRestricted(context))
            return true;
        if(isTrustedLocalResourcePath(p))
            return true;
        writeLog(0, "Blocked public request from reading local file: " + p, LOG_LEVEL_WARNING);
        return false;
    };

    if(!async)
    {
        if(find_local && fileExist(path, true) && canReadLocal(path))
            return make_ready_future(fileGet(path, true));
        if(isLink(path))
            return make_ready_future(do_webGet(path, proxy, cache_ttl));
        return make_ready_future(std::string());
    }

    std::shared_future<std::string> retVal;
    /*if(vfs::vfs_exist(path))
        retVal = std::async(std::launch::async, [path](){return vfs::vfs_get(path);});
    else */if(find_local && fileExist(path, true) && canReadLocal(path))
        retVal = std::async(std::launch::async, [path](){return fileGet(path, true);});
    else if(isLink(path))
        retVal = std::async(std::launch::async, [path, proxy, cache_ttl, user_agent](){
            if(user_agent.empty())
                return webGet(path, proxy, cache_ttl);
            string_icase_map headers;
            headers["User-Agent"] = user_agent;
            return webGet(path, proxy, cache_ttl, nullptr, &headers);
        });
    else
        return make_ready_future(std::string());
    return retVal;
}

std::string fetchFile(const std::string &path, const std::string &proxy, int cache_ttl, bool find_local, FetchContext context)
{
    return fetchFileAsync(path, proxy, cache_ttl, find_local, false, "", context).get();
}
