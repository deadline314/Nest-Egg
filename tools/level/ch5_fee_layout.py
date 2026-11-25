"""Counter fixtures for the Chapter Five receipt comparison."""

FIRST_CATCH = "ch5_pawnshop_labels_matched"
FEE_OBJECTS = {
    "fee_receipt": ("ⓤ", 54, "舊委託收據", "翻看舊委託收據"),
    "fee_ledger": ("ⓛ", 58, "手續費存款總帳", "翻看手續費存款總帳"),
}
PROMPTS = {
    "核對盤點板": ("Check the inventory board", "棚卸し板を確かめる"),
    "翻看舊委託收據": ("Read the old commission receipt", "古い依頼の領収書を読む"),
    "翻看手續費存款總帳": ("Read the fee deposit ledger", "手数料の積立帳を読む"),
}


def with_fee_objects(objects):
    """Keep the first latch on the same board used for the second comparison."""
    glyph, column, name, _ = objects["inventory_board"]
    return {
        **objects,
        "inventory_board": (glyph, column, name, "核對盤點板"),
        **FEE_OBJECTS,
    }


def gate_counter_objects(npcs):
    for ident in FEE_OBJECTS:
        npcs[f"ch5_{ident}"]["spawn_requires_flag"] = FIRST_CATCH


def stage_counter(area):
    # The register sprite includes a lamp. The usable surface sits
    # 16 world units below the sprite top.
    counter = {
        "dy": -20,
        "support": "prop",
        "support_id": "pawnshop_front__counter_register",
        "support_x": 52,
        "support_dy": 16,
    }
    area.prop("factory_office__scattered_papers", FEE_OBJECTS["fee_receipt"][1], dx=-27, **counter)
    area.prop("basement__fee_ledger", FEE_OBJECTS["fee_ledger"][1], dx=-8.5, **counter)
    board = next(entry for entry in area.props if entry["id"] == "pawnshop_front__range_tally_board")
    board["react"] = "ch5_inventory_latch"
