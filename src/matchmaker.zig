//! this should be treated as it's own binary and will be served seperately from all game code.

const std = @import("std");
const udptp = @import("udptp");
const shared = @import("shared.zig");

const HttpClient = std.http.Client;

const PacketType = shared.PacketType;
const Packet = shared.Packet;
const Server = shared.Server;
const ServerSync = shared.ServerSync;

const PORT = shared.MATCHMAKING_PORT;
const to_fixed = shared.to_fixed;

const IP_API_BASE_URL = "http://ip-api.com/json/";

const IpLocation = struct {
    continentCode: []const u8,
};

const unknown = "unknown";

fn format_uri(allocator: std.mem.Allocator, ip: [4]u8) !std.Uri {
    const url = try std.fmt.allocPrint(allocator, "{s}{d}.{d}.{d}.{d}?fields=continentCode", .{ IP_API_BASE_URL, ip[0], ip[1], ip[2], ip[3] });
    return std.Uri.parse(url);
}

const State = struct {
    /// map of all scopes
    servers: std.AutoHashMapUnmanaged(udptp.network.EndPoint, Server),

    /// if the server should stop
    should_stop: bool = false,

    http_client: HttpClient,

    allocator: std.mem.Allocator,

    timeout_interval: i64 = std.time.us_per_s * 5,

    fn init(allocator: std.mem.Allocator) State {
        return .{
            .servers = .{},
            .allocator = allocator,
            .http_client = .{ .allocator = allocator },
        };
    }
    fn deinit(self: *State) void {
        self.servers.clearAndFree(self.allocator);
        self.http_client.deinit();
    }
};

pub fn cleanup_dead_clients(self: *udptp.Server(State)) !void {
    var iter = self.clients.iterator();
    const now = std.time.microTimestamp();
    while (iter.next()) |entry| {
        const client = entry.key_ptr;
        const timestamp = entry.value_ptr;
        const delta = now - timestamp.*;

        // client is considered timed-out
        if (delta > self.ctx.timeout_interval) {
            var scopes_iter = self.ctx.servers.iterator();
            while (scopes_iter.next()) |row| {
                const host_addr = row.key_ptr.*;
                if (host_addr.port == client.port and client.address.eql(host_addr.address)) _ = self.ctx.servers.fetchRemove(host_addr);
            }
            std.log.debug("{any} timed out and got cleaned up", .{client});
            _ = self.clients.fetchRemove(entry.key_ptr.*);
        }
    }
}

pub fn handle_packet(self: *udptp.Server(State), data: []const u8, sender: udptp.network.EndPoint) udptp.PacketError!void {
    var packet = Packet.deserialize(data, self.allocator) catch return error.BadInput;
    defer packet.free(self.allocator);

    // used for sending packet
    var buffer: [1024]u8 = undefined;

    switch (packet.header.packet_type) {
        .host => {
            const aggregate = udptp.deserialize_payload(packet.payload, shared.Aggregate) catch return error.BadInput;

            const continent: shared.ContinentCode = blk: {
                if (self.ctx.servers.get(sender)) |server| {
                    break :blk server.continent;
                } else {
                    var response_buffer: std.ArrayList(u8) = .init(self.allocator);
                    const uri = format_uri(self.allocator, sender.address.ipv4.value) catch return udptp.PacketError.DeserializationError;
                    const result = self.ctx.http_client.fetch(.{ .location = .{ .uri = uri }, .response_storage = .{ .dynamic = &response_buffer } }) catch return udptp.PacketError.DeserializationError;

                    if (result.status.class() != .success) {
                        break :blk .Unknown;
                    }

                    const json_response = std.json.parseFromSlice(IpLocation, self.allocator, response_buffer.items, .{}) catch null;
                    const ip_location = if (json_response) |r| r.value else IpLocation{ .continentCode = unknown };
                    const code = std.meta.stringToEnum(shared.ContinentCode, ip_location.continentCode) orelse .Unknown;
                    std.log.err("new host from continent: {s}, continent code: {s}", .{ response_buffer.items, @tagName(code) });
                    if (json_response) |r| r.deinit();
                    response_buffer.deinit();

                    break :blk code;
                }
            };

            try self.ctx.servers.put(self.allocator, sender, .{ .aggregate = aggregate, .continent = continent });
        },
        .join => {
            const join = udptp.deserialize_payload(packet.payload, shared.JoinRequestPayload) catch return error.BadInput;
            const key: udptp.network.EndPoint = .{ .address = .{ .ipv4 = .{ .value = join.ip } }, .port = join.port };

            if (self.ctx.servers.get(key)) |server| {
                std.log.info("{} joined {}", .{ sender, server });
                const ip = sender.address.ipv4.value;
                const join_addr: shared.JoinRequestPayload = .{ .ip = ip, .port = sender.port };

                const payload = try udptp.serialize_payload(&buffer, join_addr);
                const send_packet = try Packet.init(.join, payload);
                const send_data = try send_packet.serialize(self.allocator);

                self.send_to(key, send_data);

                self.allocator.free(send_data);
            }
        },
        .close => {
            if (self.ctx.servers.fetchRemove(sender)) |server| {
                std.log.info("{} was manually closed", .{server});
            }
        },
        .req_host_list => {
            var iter = self.ctx.servers.iterator();
            var arr: std.ArrayListUnmanaged(ServerSync) = .{};
            while (iter.next()) |server| {
                const host = server.key_ptr.*;
                const ip = host.address.ipv4.value;
                const host_addr: shared.JoinRequestPayload = .{ .ip = ip, .port = host.port };
                try arr.append(self.allocator, .{ .host_addr = host_addr, .server = server.value_ptr.* });
            }
            const payload = try udptp.serialize_payload(&buffer, arr.items);
            const send_packet = try Packet.init(.ret_host_list, payload);
            const send_data = try send_packet.serialize(self.allocator);

            self.send_to(sender, send_data);

            self.allocator.free(send_data);
            arr.deinit(self.allocator);
        },
        .keepalive => {},
        else => {
            return error.BadInput;
        },
    }
}

pub fn main() !void {
    var GPA = std.heap.DebugAllocator(.{}).init;
    const allocator = GPA.allocator();

    var state = State.init(allocator);
    var server = try udptp.Server(State).init(PORT, allocator, &state);
    defer server.deinit();
    defer state.deinit();

    server.set_read_timeout(1000);

    server.handle_packet_cb = handle_packet;

    std.log.info("starting server!", .{});
    while (!state.should_stop) {
        try cleanup_dead_clients(&server);
        server.listen() catch |err| switch (err) {
            error.WouldBlock => continue,
            else => std.log.err("An error occured!\n{!}", .{err}),
        };
    }
}
