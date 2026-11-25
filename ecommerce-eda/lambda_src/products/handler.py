import common as c


def handler(event, context):
    method = event["httpMethod"]
    product_id = (event.get("pathParameters") or {}).get("id")
    products = c.table("PRODUCTS_TABLE")

    if method == "GET" and product_id:
        item = products.get_item(Key={"id": product_id}).get("Item")
        return c.response(200, item) if item else c.response(404, {"message": "Product not found"})

    if method == "GET":
        return c.response(200, products.scan(Limit=100)["Items"])

    if method == "POST":
        if "admins" not in str(c.claims(event).get("cognito:groups", "")):
            return c.response(403, {"message": "Admins only"})
        body = c.loads(event.get("body") or "{}")
        try:
            name, price = str(body["name"]).strip(), body["price"]
            assert name and price > 0
        except (KeyError, TypeError, AssertionError):
            return c.response(400, {"message": "name and a positive price are required"})
        item = {
            "id": c.new_id(),
            "name": name,
            "price": price,
            "description": body.get("description", ""),
            "created_at": c.now(),
        }
        products.put_item(Item=item)
        # Seed the stock level owned by the warehouse service
        c.table("INVENTORY_TABLE").put_item(Item={"product_id": item["id"], "stock": int(body.get("stock", 0))})
        return c.response(201, item)

    return c.response(405, {"message": "Method not allowed"})