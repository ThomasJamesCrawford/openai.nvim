local model = "gpt-3.5-turbo"
local openai_api_key = os.getenv("OPENAI_API_KEY")

local api_call_params

local function setup(parameters)
    if parameters.model then
        model = parameters.model
    end
    if parameters.openai_api_key then
        openai_api_key = parameters.openai_api_key
    end
    if parameters.api_call_params then
        api_call_params = parameters.api_call_params
    end
end

local function get_visual_selection_pos()
    local start_pos = vim.api.nvim_buf_get_mark(0, '<')
    local end_pos = vim.api.nvim_buf_get_mark(0, '>')

    return start_pos, end_pos
end

local function get_visual_selection()
    local start_pos, end_pos = get_visual_selection_pos()

    if start_pos[1] == end_pos[1] then
        -- selection is within a single line
        local line = vim.api.nvim_buf_get_lines(0, start_pos[1] - 1, start_pos[1], false)[1]
        local selection = string.sub(line, start_pos[2] + 1, end_pos[2])
        return selection
    else
        -- selection spans multiple lines
        local lines = vim.api.nvim_buf_get_lines(0, start_pos[1] - 1, end_pos[1], false)
        lines[1] = string.sub(lines[1], start_pos[2] + 1)
        lines[#lines] = string.sub(lines[#lines], 1, end_pos[2])
        local selection = table.concat(lines, '\n')
        return selection
    end
end

local function call_api(prompt)
    vim.api.nvim_command("echo ' (Loading...)'")

    local ops = api_call_params or {
        temperature = 0.9,
    }

    ops.model = model

    ops.messages = {
        {
            role = "user",
            content = prompt
        }
    }

    local data = string.format('%s', vim.fn.json_encode(ops))

    local cmd = string.format(
        [[curl -s -H "Content-Type: application/json" -H "Authorization: Bearer %s" -X POST -d %s "https://api.openai.com/v1/chat/completions"]],
        openai_api_key,
        vim.fn.shellescape(data)
    )

    local response = vim.fn.system(cmd)

    return vim.fn.json_decode(response)
end

local function explain(input, instruction)
    local prompt = instruction .. " (" ..
        vim.api.nvim_buf_get_option(0, "filetype") ..
        '). \n\n```' .. input .. '```'

    return call_api(prompt)
end

local function edit(input, instruction)
    local prompt = instruction .. " (" ..
        vim.api.nvim_buf_get_option(0, "filetype") ..
        '). \n\n```' .. input .. '```\n\n. ' ..
        "Do not return anything except the edited text."

    return call_api(prompt)
end

local function show_response(response)
    local output = response.choices[1].message.content

    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'cursor',
        row = 1,
        col = 0,
        width = math.min(80, vim.o.columns - 4),
        height = math.min(20, vim.o.lines - 4),
        style = 'minimal',
        border = {
            { "╭", "FloatBorder" },
            { "─", "FloatBorder" },
            { "╮", "FloatBorder" },
            { "│", "FloatBorder" },
            { "╯", "FloatBorder" },
            { "─", "FloatBorder" },
            { "╰", "FloatBorder" },
            { "│", "FloatBorder" },
        }
    })
    vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

    local lines = {}
    for line in output:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    -- insert the response into the buffer
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- focus the window
    vim.api.nvim_set_current_win(win)
end

local function insert_response(response)
    local start_pos, end_pos = get_visual_selection_pos()

    local output_lines = vim.split(response.choices[1].message.content, "\n", {})

    vim.api.nvim_buf_set_lines(0, start_pos[1] - 1, end_pos[1], false, output_lines)
end

vim.api.nvim_create_user_command(
    'OpenAICompletion',
    function(opts)
        local prompt = vim.fn.input("Enter your prompt: ")
        local selection = get_visual_selection()
        local res = explain(selection, prompt)

        show_response(res)
    end, { range = true }
)

vim.api.nvim_create_user_command(
    'OpenAICompletionEdit',
    function()
        local prompt = vim.fn.input("Enter your prompt: ")
        local selection = get_visual_selection()
        local res = edit(selection, prompt)

        insert_response(res)
    end, {}
)

return {
    setup = setup,
}
