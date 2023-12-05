---
feature: nixos-cli
start-date: 2023-12-05
author: Varun Narravula
co-authors: David Arnold, Ghost User
shepherd-leader: Shadow Knight
shepherd-team: Secret Pumpkin, Swift Shadow, King Nix
related-issues: https://github.com/NixOS/nixpkgs/issues/54188, https://github.com/NixOS/nixpkgs/issues/51198, TBD
---

# Summary
[summary]: #summary

Design and implement an official, modular and extensible `nixos` CLI tool.

# Motivation
[motivation]: #motivation

There are two initial motivating factors:
 - Nix (`nixos/nix`) slowly evolves into a more modular layout and needs to clean up its interface
 - There are 7+ choreographing `nixos-*` commands in Nixpkgs with low levels of integration


## Needs of an evolving Nix (`nixos/nix`)

As detailed in a [Discourse post](https://discourse.nixos.org/t/nixpkgs-cli-working-group-member-search/30517), Nix
and Nixpkgs are not clearly separated and concepts that purely belong to Nixpkgs (e.g. `pname`) bleed into the
implementation of Nix.

While cleaning up the design of Nix proper, a canonical place is required to suplement these use cases from within Nixpkgs.

This is a increasingly pressing technical requirement from Nix proper.

## A better integrated UX for NixOS

In hopes of not missing one, there are currently, at least:
```
nixos-rebuild
nixos-container
nixos-enter
nixos-generate-config
nixos-install
nixos-version
nixos-help
```

Some areas of shortcomings are:

- Command Line Completion, dynamic and static
- Flag / Option consistency
- Balancing what newbies and power-users expect from a CLI
- Good and consistent error handling and friendly help messages

# Propositions
[propositions]: #propositions

This RFC request fundamental (and not more) consensus on the following two headlined statements.

## "We need a consolidated `nixos` CLI implementation"

Create a single command (`nixos`) that unifies and simplifies common NixOS interactions for better user experience, stability and maintainability.

Note: this RFC only regards `nixos`; other tooling around Nixpkgs may be considered in a different RFC.

## "We need a UX-centric redesign of such `nixos`"

To exemplify, we provide an initial brainstorm:

**No complete nor authoritative list; flags ommited to emphasize the lack of specificity of the example**

```console
# main commands
nixos init    # bootsrap a configuration
nixos format  # use disko to format the disks (get specialists on board to make this somewhat safe)
nixos install # install local or remote
nixos list    # interact with generations (including rollback/gc/etc)
nixos peek    # peek into a system either via chroot or vm or other means, if there are
nixos info    # "run this and post the result whenever you ask for help somewhere"
nixos apply   # reconcile your system to comply with your configuration

# topic commands with subcommands
nixos docs ...
nixos containers ...
nixos [my-plugin] ...
```

As you can see, the goal is roughly to capture the intent of the user in her naive words in the shortest and uncontrived possible way, even if that user is a newcomer to the NixOS world.

# Roadmap
[roadmap]: #roadmap

**This section is for context and inspirational purposes only and not fixed nor subject of this RFC; We invite interested parties to join the discussion about the roadmap after consensus is reached in a different place.**

- **Research and Familiarization:**
    - Gain a deep understanding of NixOS and its various commands.
    - Explore existing tools and commands used in NixOS.
    - Consider upcoming community tools, in addition to mainstreamed tools.
    - Document your findings.
- **Define Command Structure:**
    - Identify the key functionalities of NixOS commands that need to be unified.
    - Design a modular command structure that can accommodate various functionalities.
    - Design for a plugin system to provide a canonical way for community innovations.
- **Implement Basic Functionality:**
    - Start with a basic implementation that can execute simple NixOS commands.
    - Wrap existing (shell) commands to provide significant value quickly before refactoring them later.
    - Focus on functionality such as activation, installation and bootstrapping.
- **Command Line Interface (CLI):**
    - Design a user-friendly CLI with clear and concise commands.
    - Implement options and flags for various functionalities.
    - Roll back on technicisms that require too much prerequisite knowledge and prefer easy, clear commands that are self-explanatory to all user levels.
- **Handle Configuration Bootstrapping:**
    - Address configuration handling, in the context of repository based or local configuration.
    - Develop maintenance mechanisms to maintain and update NixOS configurations using the unified command.
- **Testing:**
    - Implement comprehensive testing to ensure the new command works with various NixOS setups.
    - Incorporate testing into Nixpkgs test infrastructure.
    - Adopt test driven design method where/if appropriate.
7. **Documentation:**
    - Create detailed documentation for the unified command.
    - Include usage examples, command syntax, and potential use cases.
    - Consider automatic source-based documentation tooling to keep maintenance overhead low.
8. **Community Engagement:**
    - Share your project with the NixOS community.
    - Gather feedback and suggestions for improvement.
    - Collaborate with the community to refine and enhance the unified command.
    - Write a tutorial how to write a plugin in a language of choice.
9. **Write eventual follow up RFCs:**
    - Share your lessens learnt and design choices via the RFC process to the broader community.
    - Request consens on this new endeavor with motion to upstream into Nixpkgs.
    - Remove any blockers for consensus as they come up via the RFC feedback.
10. **Security Considerations:**
    - Ensure that the unified command follows best practices for security.
    - Implement safeguards to prevent unintended consequences.
11. **Error Handling:**
    - Implement robust error handling to provide meaningful error messages.
    - Include troubleshooting information in the documentation.
12. **Optimization and Performance:**
    - Optimize the unified command for performance.
    - Consider caching mechanisms for repeated operations.
13. **Versioning:**
    - Implement versioning for the unified command to manage changes and updates.
    - Communicate changes clearly in release notes.
14. **Maintenance Plan:**
    - Develop a plan for ongoing maintenance and updates.
    - Consider creating a community-driven project for long-term sustainability.
15. **Release:**
    - Prepare for the initial release.
    - Share the unified command through package managers or other distribution channels.
16. **Feedback Loop:**
    - Encourage users to provide feedback.
    - Iterate on the command based on user experiences and suggestions.

## Considerations:

- **Community Involvement:** Engage with the NixOS community early and often to ensure your efforts align with community needs and standards.
- **Backward Compatibility:** Ensure compatibility with existing NixOS commands and configurations to minimize disruption for users. To not constrain innovation, use a compatibility frontend / compile target.
- **Forward Compatibility:** Cater to flake users by providing a flake-support via a flake-only frontend / build target and avoid flag expansion for that purpose.
- **Usability:** Prioritize a simple and intuitive user interface to make the unified command accessible to both beginners and experienced users.
- **Documentation and Support:** Comprehensive documentation is crucial for user adoption. Provide support channels for users to seek help and share experiences.
