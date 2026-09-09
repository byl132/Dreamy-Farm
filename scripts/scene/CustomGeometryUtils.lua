local CustomGeometryUtils = {}

local cache = nil

function CustomGeometryUtils.SetCache(c)
    cache = c
end

function CustomGeometryUtils.CreateTerrainMesh(scene, name, width, depth, segments, heightFunc, mat)
    local node = scene:CreateChild(name)
    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    local stepX = width / segments
    local stepZ = depth / segments

    local vertices = {}

    for z = 0, segments do
        for x = 0, segments do
            local px = (x - segments / 2) * stepX
            local pz = (z - segments / 2) * stepZ
            local py = heightFunc(px, pz)

            vertices[#vertices + 1] = { Vector3(px, py, pz), Vector3(0, 1, 0), Vector2(x / segments, z / segments) }
        end
    end

    for z = 0, segments - 1 do
        for x = 0, segments - 1 do
            local i = z * (segments + 1) + x + 1

            local v1 = vertices[i]
            local v2 = vertices[i + 1]
            local v3 = vertices[i + segments + 1]

            geom:DefineVertex(v1[1])
            geom:DefineNormal(v1[2])
            geom:DefineTexCoord(v1[3])

            geom:DefineVertex(v2[1])
            geom:DefineNormal(v2[2])
            geom:DefineTexCoord(v2[3])

            geom:DefineVertex(v3[1])
            geom:DefineNormal(v3[2])
            geom:DefineTexCoord(v3[3])

            local v4 = vertices[i + 1]
            local v5 = vertices[i + segments + 2]
            local v6 = vertices[i + segments + 1]

            geom:DefineVertex(v4[1])
            geom:DefineNormal(v4[2])
            geom:DefineTexCoord(v4[3])

            geom:DefineVertex(v5[1])
            geom:DefineNormal(v5[2])
            geom:DefineTexCoord(v5[3])

            geom:DefineVertex(v6[1])
            geom:DefineNormal(v6[2])
            geom:DefineTexCoord(v6[3])
        end
    end

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreateGrassPatch(scene, name, pos, width, depth, density, mat)
    local node = scene:CreateChild(name)
    node.position = pos

    for i = 1, density do
        local px = (math.random() - 0.5) * width
        local pz = (math.random() - 0.5) * depth
        local scale = 0.3 + math.random() * 0.4
        local angle = math.random() * 360

        local grassNode = node:CreateChild("Grass_" .. i)
        grassNode.position = Vector3(px, 0, pz)
        grassNode.rotation = Quaternion(math.random() * 15 - 7, angle, math.random() * 15 - 7)
        grassNode.scale = Vector3(scale * 0.2, scale, scale * 0.2)

        local geom = grassNode:CreateComponent("CustomGeometry")
        geom:BeginGeometry(0, TRIANGLE_LIST)

        geom:DefineVertex(Vector3(0, 0, 0))
        geom:DefineVertex(Vector3(0.15, 0.8, 0))
        geom:DefineVertex(Vector3(-0.15, 1.0, 0))

        geom:DefineVertex(Vector3(0.15, 0.8, 0))
        geom:DefineVertex(Vector3(0.12, 0.6, 0))
        geom:DefineVertex(Vector3(-0.15, 1.0, 0))

        geom:DefineVertex(Vector3(0.15, 0.8, 0))
        geom:DefineVertex(Vector3(-0.15, 1.0, 0))
        geom:DefineVertex(Vector3(0, 1.2, 0))

        geom:DefineVertex(Vector3(0.15, 0.8, 0))
        geom:DefineVertex(Vector3(0.12, 0.6, 0))
        geom:DefineVertex(Vector3(-0.15, 1.0, 0))

        geom:DefineVertex(Vector3(-0.15, 1.0, 0))
        geom:DefineVertex(Vector3(-0.12, 0.7, 0))
        geom:DefineVertex(Vector3(0, 1.2, 0))

        geom:Commit()
        geom:SetMaterial(mat)
    end

    return node
end

function CustomGeometryUtils.CreateTreeTrunk(scene, name, pos, height, radius, mat)
    local node = scene:CreateChild(name)
    node.position = pos

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    local segments = 8

    for i = 0, segments do
        local i1 = i % segments
        local i2 = (i + 1) % segments

        local angle1 = i1 * 360 / segments
        local angle2 = i2 * 360 / segments

        local cx1 = math.sin(angle1 * math.pi / 180) * radius
        local cz1 = math.cos(angle1 * math.pi / 180) * radius
        local cx2 = math.sin(angle2 * math.pi / 180) * radius
        local cz2 = math.cos(angle2 * math.pi / 180) * radius

        geom:DefineVertex(Vector3(cx1, 0, cz1))
        geom:DefineVertex(Vector3(cx1 * 0.3, height, cz1 * 0.3))
        geom:DefineVertex(Vector3(cx2, 0, cz2))

        geom:DefineVertex(Vector3(cx1 * 0.3, height, cz1 * 0.3))
        geom:DefineVertex(Vector3(cx2 * 0.3, height, cz2 * 0.3))
        geom:DefineVertex(Vector3(cx2, 0, cz2))
    end

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreateTreeFoliage(scene, name, pos, baseRadius, height, layers, mat)
    local node = scene:CreateChild(name)
    node.position = pos

    local stepY = height / layers

    for layer = 0, layers do
        local layerY = layer * stepY
        local layerRadius = baseRadius * (1 - layer / (layers * 1.5))

        local geom = node:CreateComponent("CustomGeometry")
        geom:BeginGeometry(layer, TRIANGLE_FAN)

        geom:DefineVertex(Vector3(0, layerY, 0))

        local segments = 12 + layer * 2
        for i = 0, segments do
            local angle = i * 360 / segments
            local rx = math.sin(angle * math.pi / 180) * layerRadius
            local rz = math.cos(angle * math.pi / 180) * layerRadius
            geom:DefineVertex(Vector3(rx, layerY, rz))
        end

        geom:Commit()
        geom:SetMaterial(mat)
    end

    return node
end

function CustomGeometryUtils.CreateBuildingWall(scene, name, pos, width, height, depth, mat)
    local node = scene:CreateChild(name)
    node.position = pos

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    local hw = width / 2
    local hh = height
    local hd = depth / 2

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, -hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, -hd))
    geom:DefineVertex(Vector3(-hw, hh, -hd))

    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(hw, 0, hd))
    geom:DefineVertex(Vector3(hw, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(hw, hh, hd))
    geom:DefineVertex(Vector3(-hw, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(-hw, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(-hw, hh, hd))
    geom:DefineVertex(Vector3(-hw, hh, -hd))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, -hd))
    geom:DefineVertex(Vector3(hw, hh, hd))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, hd))
    geom:DefineVertex(Vector3(hw, 0, hd))

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreateGabledRoof(scene, name, pos, width, depth, height, mat)
    local node = scene:CreateChild(name)
    node.position = pos

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    local hw = width / 2
    local hd = depth / 2
    local hh = height

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(0, hh, -hd))

    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(hw, 0, hd))
    geom:DefineVertex(Vector3(0, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(0, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(0, hh, hd))
    geom:DefineVertex(Vector3(0, hh, -hd))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, 0, hd))
    geom:DefineVertex(Vector3(0, hh, hd))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(0, hh, hd))
    geom:DefineVertex(Vector3(0, hh, -hd))

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreateBush(scene, name, pos, radius, density, mat)
    local node = scene:CreateChild(name)
    node.position = pos

    local numSpheres = density or 8
    local baseRadius = radius

    for i = 1, numSpheres do
        local angle = math.random() * 360
        local dist = math.random() * baseRadius * 0.6
        local height = math.random() * baseRadius * 0.8
        local scale = baseRadius * (0.4 + math.random() * 0.5)

        local bushNode = node:CreateChild("BushPart_" .. i)
        bushNode.position = Vector3(
            math.sin(angle * math.pi / 180) * dist,
            height,
            math.cos(angle * math.pi / 180) * dist
        )
        bushNode.scale = Vector3(scale, scale * 0.7, scale)

        local geom = bushNode:CreateComponent("CustomGeometry")
        geom:BeginGeometry(0, TRIANGLE_FAN)

        geom:DefineVertex(Vector3(0, 0, 0))

        local segments = 16
        for seg = 0, segments do
            local theta = seg * math.pi / segments
            for j = 0, segments do
                local phi = j * 2 * math.pi / segments
                local x = math.sin(theta) * math.cos(phi)
                local y = math.cos(theta)
                local z = math.sin(theta) * math.sin(phi)
                geom:DefineVertex(Vector3(x, y, z))
            end
        end

        geom:Commit()
        geom:SetMaterial(mat)
    end

    return node
end

function CustomGeometryUtils.CreateRock(scene, name, pos, scale, mat)
    local node = scene:CreateChild(name)
    node.position = pos
    node.scale = Vector3(scale, scale * 0.6, scale * 0.8)

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    geom:DefineVertex(Vector3(0, 0.5, 0))
    geom:DefineVertex(Vector3(0.4, 0.3, 0.3))
    geom:DefineVertex(Vector3(-0.35, 0.25, 0.25))

    geom:DefineVertex(Vector3(0, 0.5, 0))
    geom:DefineVertex(Vector3(-0.35, 0.25, 0.25))
    geom:DefineVertex(Vector3(-0.4, 0.2, -0.25))

    geom:DefineVertex(Vector3(0, 0.5, 0))
    geom:DefineVertex(Vector3(-0.4, 0.2, -0.25))
    geom:DefineVertex(Vector3(0.3, 0.15, -0.35))

    geom:DefineVertex(Vector3(0, 0.5, 0))
    geom:DefineVertex(Vector3(0.3, 0.15, -0.35))
    geom:DefineVertex(Vector3(0.4, 0.3, 0.3))

    geom:DefineVertex(Vector3(0.4, 0.3, 0.3))
    geom:DefineVertex(Vector3(0.3, 0.15, -0.35))
    geom:DefineVertex(Vector3(0.25, 0, 0.4))

    geom:DefineVertex(Vector3(0.4, 0.3, 0.3))
    geom:DefineVertex(Vector3(0.25, 0, 0.4))
    geom:DefineVertex(Vector3(-0.35, 0.25, 0.25))

    geom:DefineVertex(Vector3(-0.35, 0.25, 0.25))
    geom:DefineVertex(Vector3(0.25, 0, 0.4))
    geom:DefineVertex(Vector3(-0.3, -0.1, 0.3))

    geom:DefineVertex(Vector3(-0.35, 0.25, 0.25))
    geom:DefineVertex(Vector3(-0.3, -0.1, 0.3))
    geom:DefineVertex(Vector3(-0.4, 0.2, -0.25))

    geom:DefineVertex(Vector3(-0.4, 0.2, -0.25))
    geom:DefineVertex(Vector3(-0.3, -0.1, 0.3))
    geom:DefineVertex(Vector3(0, -0.2, 0))

    geom:DefineVertex(Vector3(-0.4, 0.2, -0.25))
    geom:DefineVertex(Vector3(0, -0.2, 0))
    geom:DefineVertex(Vector3(-0.25, -0.1, -0.3))

    geom:DefineVertex(Vector3(-0.4, 0.2, -0.25))
    geom:DefineVertex(Vector3(-0.25, -0.1, -0.3))
    geom:DefineVertex(Vector3(0.3, 0.15, -0.35))

    geom:DefineVertex(Vector3(0.3, 0.15, -0.35))
    geom:DefineVertex(Vector3(-0.25, -0.1, -0.3))
    geom:DefineVertex(Vector3(0.2, -0.15, -0.4))

    geom:DefineVertex(Vector3(0.3, 0.15, -0.35))
    geom:DefineVertex(Vector3(0.2, -0.15, -0.4))
    geom:DefineVertex(Vector3(0.25, 0, 0.4))

    geom:DefineVertex(Vector3(0.25, 0, 0.4))
    geom:DefineVertex(Vector3(0.2, -0.15, -0.4))
    geom:DefineVertex(Vector3(0, -0.2, 0))

    geom:DefineVertex(Vector3(0.25, 0, 0.4))
    geom:DefineVertex(Vector3(0, -0.2, 0))
    geom:DefineVertex(Vector3(-0.3, -0.1, 0.3))

    geom:DefineVertex(Vector3(-0.3, -0.1, 0.3))
    geom:DefineVertex(Vector3(0, -0.2, 0))
    geom:DefineVertex(Vector3(-0.25, -0.1, -0.3))

    geom:DefineVertex(Vector3(0.2, -0.15, -0.4))
    geom:DefineVertex(Vector3(-0.25, -0.1, -0.3))
    geom:DefineVertex(Vector3(0, -0.2, 0))

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreateFlower(scene, name, pos, petalCount, color, stemMat)
    local node = scene:CreateChild(name)
    node.position = pos

    local stemNode = node:CreateChild("Stem")
    stemNode.scale = Vector3(0.03, 0.6, 0.03)

    local stemGeom = stemNode:CreateComponent("CustomGeometry")
    stemGeom:BeginGeometry(0, TRIANGLE_LIST)

    stemGeom:DefineVertex(Vector3(0, 0, 0))
    stemGeom:DefineVertex(Vector3(0.03, 0, 0))
    stemGeom:DefineVertex(Vector3(0.03, 0.6, 0))

    stemGeom:DefineVertex(Vector3(0, 0, 0))
    stemGeom:DefineVertex(Vector3(0.03, 0.6, 0))
    stemGeom:DefineVertex(Vector3(0, 0.6, 0))

    stemGeom:Commit()
    stemGeom:SetMaterial(stemMat)

    local flowerNode = node:CreateChild("Flower")
    flowerNode.position = Vector3(0, 0.62, 0)
    flowerNode.scale = Vector3(0.3, 0.3, 0.3)

    local flowerGeom = flowerNode:CreateComponent("CustomGeometry")
    flowerGeom:BeginGeometry(0, TRIANGLE_LIST)

    local center = Vector3(0, 0.25, 0)
    flowerGeom:DefineVertex(center)

    for i = 1, petalCount do
        local angle = (i - 1) * 360 / petalCount
        local px = math.sin(angle * math.pi / 180) * 0.5
        local pz = math.cos(angle * math.pi / 180) * 0.5

        local petalBase = Vector3(px, 0, pz)
        local petalTip = Vector3(px * 0.3, 0.3, pz * 0.3)

        flowerGeom:DefineVertex(petalBase)
        flowerGeom:DefineVertex(petalTip)
        flowerGeom:DefineVertex(center)
    end

    flowerGeom:Commit()

    local petalMat = Material:new()
    petalMat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    petalMat:SetShaderParameter("MatDiffColor", Variant(color))
    petalMat:SetShaderParameter("MatSpecColor", Variant(Color(0.5, 0.5, 0.5, 1.0)))
    petalMat:SetShaderParameter("Metallic", Variant(0.0))
    petalMat:SetShaderParameter("Roughness", Variant(0.15))
    flowerGeom:SetMaterial(petalMat)

    return node
end

function CustomGeometryUtils.CreateLake(scene, name, pos, width, depth, mat)
    local node = scene:CreateChild(name)
    node.position = pos

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    local hw = width / 2
    local hd = depth / 2

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, 0, hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, 0, hd))
    geom:DefineVertex(Vector3(-hw, 0, hd))

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreateHill(scene, name, pos, radius, height, mat)
    local node = scene:CreateChild(name)
    node.position = pos
    node.scale = Vector3(radius, height, radius)

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_FAN)

    geom:DefineVertex(Vector3(0, 1, 0))

    local segments = 16
    for i = 0, segments do
        local angle = i * 360 / segments
        local x = math.sin(angle * math.pi / 180)
        local z = math.cos(angle * math.pi / 180)
        geom:DefineVertex(Vector3(x, 0, z))
    end

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreatePath(scene, name, points, width, mat)
    local node = scene:CreateChild(name)

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    for i = 1, #points - 1 do
        local p1 = points[i]
        local p2 = points[i + 1]

        local dir = p2 - p1
        dir.y = 0
        dir = dir:Normalized()

        local perp = Vector3(-dir.z, 0, dir.x) * (width / 2)

        local v1 = Vector3(p1.x + perp.x, 0.02, p1.z + perp.z)
        local v2 = Vector3(p1.x - perp.x, 0.02, p1.z - perp.z)
        local v3 = Vector3(p2.x + perp.x, 0.02, p2.z + perp.z)
        local v4 = Vector3(p2.x - perp.x, 0.02, p2.z - perp.z)

        geom:DefineVertex(v1)
        geom:DefineVertex(v2)
        geom:DefineVertex(v3)

        geom:DefineVertex(v2)
        geom:DefineVertex(v4)
        geom:DefineVertex(v3)
    end

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreateSlopedRoof(scene, name, pos, width, depth, height, mat)
    local node = scene:CreateChild(name)
    node.position = pos

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    local hw = width / 2
    local hd = depth / 2
    local hh = height

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(0, hh, -hd))

    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(hw, 0, hd))
    geom:DefineVertex(Vector3(0, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(0, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(0, hh, hd))
    geom:DefineVertex(Vector3(0, hh, -hd))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, 0, hd))
    geom:DefineVertex(Vector3(0, hh, hd))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(0, hh, hd))
    geom:DefineVertex(Vector3(0, hh, -hd))

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreateCylinderGeom(scene, name, pos, radius, height, segments, mat)
    local node = scene:CreateChild(name)
    node.position = pos

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    segments = segments or 8

    for i = 0, segments do
        local i1 = i % segments
        local i2 = (i + 1) % segments

        local angle1 = i1 * 360 / segments
        local angle2 = i2 * 360 / segments

        local cx1 = math.sin(angle1 * math.pi / 180) * radius
        local cz1 = math.cos(angle1 * math.pi / 180) * radius
        local cx2 = math.sin(angle2 * math.pi / 180) * radius
        local cz2 = math.cos(angle2 * math.pi / 180) * radius

        geom:DefineVertex(Vector3(cx1, 0, cz1))
        geom:DefineVertex(Vector3(cx1, height, cz1))
        geom:DefineVertex(Vector3(cx2, 0, cz2))

        geom:DefineVertex(Vector3(cx1, height, cz1))
        geom:DefineVertex(Vector3(cx2, height, cz2))
        geom:DefineVertex(Vector3(cx2, 0, cz2))
    end

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreateWindowFrame(scene, name, pos, width, height, depth, frameMat, glassMat)
    local node = scene:CreateChild(name)
    node.position = pos

    local hw = width / 2
    local hh = height / 2
    local hd = depth / 2

    local glassNode = node:CreateChild("Glass")
    local glassGeom = glassNode:CreateComponent("CustomGeometry")
    glassGeom:BeginGeometry(0, TRIANGLE_LIST)
    glassGeom:DefineVertex(Vector3(-hw, -hh, -hd))
    glassGeom:DefineVertex(Vector3(hw, -hh, -hd))
    glassGeom:DefineVertex(Vector3(hw, hh, -hd))
    glassGeom:DefineVertex(Vector3(-hw, -hh, -hd))
    glassGeom:DefineVertex(Vector3(hw, hh, -hd))
    glassGeom:DefineVertex(Vector3(-hw, hh, -hd))
    glassGeom:Commit()
    glassGeom:SetMaterial(glassMat)

    local frameNode = node:CreateChild("Frame")
    local frameGeom = frameNode:CreateComponent("CustomGeometry")
    frameGeom:BeginGeometry(0, TRIANGLE_LIST)

    local frameThickness = 0.12

    frameGeom:DefineVertex(Vector3(-hw - frameThickness, -hh - frameThickness, hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, -hh - frameThickness, hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, hh + frameThickness, hd))
    frameGeom:DefineVertex(Vector3(-hw - frameThickness, -hh - frameThickness, hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, hh + frameThickness, hd))
    frameGeom:DefineVertex(Vector3(-hw - frameThickness, hh + frameThickness, hd))

    frameGeom:DefineVertex(Vector3(-hw - frameThickness, -hh - frameThickness, -hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, -hh - frameThickness, -hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, hh + frameThickness, -hd))
    frameGeom:DefineVertex(Vector3(-hw - frameThickness, -hh - frameThickness, -hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, hh + frameThickness, -hd))
    frameGeom:DefineVertex(Vector3(-hw - frameThickness, hh + frameThickness, -hd))

    frameGeom:DefineVertex(Vector3(-hw - frameThickness, -hh, -hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, -hh, -hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, -hh, hd))
    frameGeom:DefineVertex(Vector3(-hw - frameThickness, -hh, -hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, -hh, hd))
    frameGeom:DefineVertex(Vector3(-hw - frameThickness, -hh, hd))

    frameGeom:DefineVertex(Vector3(-hw - frameThickness, hh, -hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, hh, -hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, hh, hd))
    frameGeom:DefineVertex(Vector3(-hw - frameThickness, hh, -hd))
    frameGeom:DefineVertex(Vector3(hw + frameThickness, hh, hd))
    frameGeom:DefineVertex(Vector3(-hw - frameThickness, hh, hd))

    frameGeom:DefineVertex(Vector3(-hw, -hh - frameThickness, -hd))
    frameGeom:DefineVertex(Vector3(-hw, hh + frameThickness, -hd))
    frameGeom:DefineVertex(Vector3(-hw, hh + frameThickness, hd))
    frameGeom:DefineVertex(Vector3(-hw, -hh - frameThickness, -hd))
    frameGeom:DefineVertex(Vector3(-hw, hh + frameThickness, hd))
    frameGeom:DefineVertex(Vector3(-hw, -hh - frameThickness, hd))

    frameGeom:DefineVertex(Vector3(hw, -hh - frameThickness, -hd))
    frameGeom:DefineVertex(Vector3(hw, hh + frameThickness, -hd))
    frameGeom:DefineVertex(Vector3(hw, hh + frameThickness, hd))
    frameGeom:DefineVertex(Vector3(hw, -hh - frameThickness, -hd))
    frameGeom:DefineVertex(Vector3(hw, hh + frameThickness, hd))
    frameGeom:DefineVertex(Vector3(hw, -hh - frameThickness, hd))

    frameGeom:Commit()
    frameGeom:SetMaterial(frameMat)

    return node
end

function CustomGeometryUtils.CreateChimney(scene, name, pos, width, depth, height, mat)
    local node = scene:CreateChild(name)
    node.position = pos

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    local hw = width / 2
    local hh = height
    local hd = depth / 2

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, -hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, -hd))
    geom:DefineVertex(Vector3(-hw, hh, -hd))

    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(hw, 0, hd))
    geom:DefineVertex(Vector3(hw, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(hw, hh, hd))
    geom:DefineVertex(Vector3(-hw, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(-hw, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(-hw, hh, hd))
    geom:DefineVertex(Vector3(-hw, hh, -hd))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, -hd))
    geom:DefineVertex(Vector3(hw, hh, hd))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, hd))
    geom:DefineVertex(Vector3(hw, 0, hd))

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreateDoor(scene, name, pos, width, height, depth, mat)
    local node = scene:CreateChild(name)
    node.position = pos

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    local hw = width / 2
    local hh = height
    local hd = depth / 2

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, -hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, -hd))
    geom:DefineVertex(Vector3(-hw, hh, -hd))

    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(hw, 0, hd))
    geom:DefineVertex(Vector3(hw, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(hw, hh, hd))
    geom:DefineVertex(Vector3(-hw, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(-hw, hh, hd))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(-hw, hh, hd))
    geom:DefineVertex(Vector3(-hw, hh, -hd))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, -hd))
    geom:DefineVertex(Vector3(hw, hh, hd))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, hh, hd))
    geom:DefineVertex(Vector3(hw, 0, hd))

    geom:Commit()
    geom:SetMaterial(mat)
    return node
end

function CustomGeometryUtils.CreateFlowerPot(scene, name, pos, width, height, depth, potMat)
    local node = scene:CreateChild(name)
    node.position = pos

    local geom = node:CreateComponent("CustomGeometry")
    geom:BeginGeometry(0, TRIANGLE_LIST)

    local hw = width / 2
    local hh = height
    local hd = depth / 2

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw * 0.85, hh, -hd * 0.85))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(hw * 0.85, hh, -hd * 0.85))
    geom:DefineVertex(Vector3(-hw * 0.85, hh, -hd * 0.85))

    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(hw, 0, hd))
    geom:DefineVertex(Vector3(hw * 0.85, hh, hd * 0.85))

    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(hw * 0.85, hh, hd * 0.85))
    geom:DefineVertex(Vector3(-hw * 0.85, hh, hd * 0.85))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(-hw, 0, hd))
    geom:DefineVertex(Vector3(-hw * 0.85, hh, hd * 0.85))

    geom:DefineVertex(Vector3(-hw, 0, -hd))
    geom:DefineVertex(Vector3(-hw * 0.85, hh, hd * 0.85))
    geom:DefineVertex(Vector3(-hw * 0.85, hh, -hd * 0.85))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw * 0.85, hh, -hd * 0.85))
    geom:DefineVertex(Vector3(hw * 0.85, hh, hd * 0.85))

    geom:DefineVertex(Vector3(hw, 0, -hd))
    geom:DefineVertex(Vector3(hw * 0.85, hh, hd * 0.85))
    geom:DefineVertex(Vector3(hw, 0, hd))

    geom:Commit()
    geom:SetMaterial(potMat)
    return node
end

function CustomGeometryUtils.CreateRoofTiles(scene, name, pos, width, depth, rows, cols, tileMat)
    local node = scene:CreateChild(name)
    node.position = pos

    local tileWidth = width / cols
    local tileDepth = depth / rows

    for row = 0, rows - 1 do
        for col = 0, cols - 1 do
            local tileNode = node:CreateChild("Tile_" .. row .. "_" .. col)
            tileNode.position = Vector3(
                -width / 2 + col * tileWidth + tileWidth / 2,
                (row % 2) * 0.03,
                -depth / 2 + row * tileDepth + tileDepth / 2
            )
            tileNode.scale = Vector3(tileWidth * 0.95, 0.06, tileDepth * 0.95)

            local geom = tileNode:CreateComponent("CustomGeometry")
            geom:BeginGeometry(0, TRIANGLE_LIST)

            geom:DefineVertex(Vector3(-0.5, 0, -0.5))
            geom:DefineVertex(Vector3(0.5, 0, -0.5))
            geom:DefineVertex(Vector3(0.5, 0.06, -0.5))

            geom:DefineVertex(Vector3(-0.5, 0, -0.5))
            geom:DefineVertex(Vector3(0.5, 0.06, -0.5))
            geom:DefineVertex(Vector3(-0.5, 0.06, -0.5))

            geom:DefineVertex(Vector3(-0.5, 0, 0.5))
            geom:DefineVertex(Vector3(0.5, 0, 0.5))
            geom:DefineVertex(Vector3(0.5, 0.06, 0.5))

            geom:DefineVertex(Vector3(-0.5, 0, 0.5))
            geom:DefineVertex(Vector3(0.5, 0.06, 0.5))
            geom:DefineVertex(Vector3(-0.5, 0.06, 0.5))

            geom:DefineVertex(Vector3(-0.5, 0, -0.5))
            geom:DefineVertex(Vector3(-0.5, 0, 0.5))
            geom:DefineVertex(Vector3(-0.5, 0.06, 0.5))

            geom:DefineVertex(Vector3(-0.5, 0, -0.5))
            geom:DefineVertex(Vector3(-0.5, 0.06, 0.5))
            geom:DefineVertex(Vector3(-0.5, 0.06, -0.5))

            geom:DefineVertex(Vector3(0.5, 0, -0.5))
            geom:DefineVertex(Vector3(0.5, 0.06, -0.5))
            geom:DefineVertex(Vector3(0.5, 0.06, 0.5))

            geom:DefineVertex(Vector3(0.5, 0, -0.5))
            geom:DefineVertex(Vector3(0.5, 0.06, 0.5))
            geom:DefineVertex(Vector3(0.5, 0, 0.5))

            geom:Commit()
            geom:SetMaterial(tileMat)
        end
    end

    return node
end

return CustomGeometryUtils