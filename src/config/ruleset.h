#ifndef RULESET_H_INCLUDED
#define RULESET_H_INCLUDED

#include "def.h"

enum class RulesetType
{
    SurgeRuleset,
    QuantumultX,
    ClashDomain,
    ClashIpCidr,
    ClashClassic
};

struct RulesetConfig
{
    String Group;
    //RulesetType Type = RulesetType::SurgeRuleset;
    String Url;
    Integer Interval = 0;
    String UserAgent;  // per-rule User-Agent: set via "ua=" in INI or "user_agent" in TOML
    String Proxy;      // per-rule proxy for rule-provider: set via "proxy=" in INI or "proxy" in TOML
    bool Provider = false;  // if true, generate rule-provider; if false, server-side fetch & inline expand
    bool provider_explicit = false;  // if true, ,provider= was explicitly set in config (distinguishes from default/global)
    bool provider_override = false;  // if true, &rules-provider= global was applied (overrides &classic=)
    bool operator==(const RulesetConfig &r) const
    {
        return Group == r.Group && Url == r.Url && Interval == r.Interval;
    }
};

using RulesetConfigs = std::vector<RulesetConfig>;

#endif // RULESET_H_INCLUDED
